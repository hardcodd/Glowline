import Foundation
import MetalKit

enum RenderFailure: Error { case unavailable(String) }

/// Completion timestamps measure GPU work, while host frame intervals measure visible pacing separately.
final class FrameMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    private var failures = 0
    func record(_ buffer: MTLCommandBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if buffer.status == .error { failures += 1 }
        let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
        if ms > 0 { times.append(ms) }
        if times.count > 1200 { times.removeFirst(times.count - 1200) }
    }
    func snapshot() -> (median: Double, p95: Double, max: Double, errors: Int, samples: Int) {
        lock.lock()
        defer { lock.unlock() }
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0, failures, 0) }
        return (
            sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            sorted.last!, failures, sorted.count
        )
    }
}

/// A reusable native renderer: no window, browser, serial controller or Glowline preferences are owned here.
final class MetalRenderer {
    static let capacity = 32768
    let device: MTLDevice
    let metrics = FrameMetrics()
    private let queue: MTLCommandQueue
    private let compute: MTLComputePipelineState
    private let gatherChunks: MTLComputePipelineState
    private let chunkIndices: MTLBuffer
    private let chunkArguments: MTLBuffer
    private let bodies: MTLRenderPipelineState
    private let impactFlashes: MTLRenderPipelineState
    private let chunks: MTLRenderPipelineState
    private let material: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private let ground: MTLRenderPipelineState
    private let emberGround: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthRead: MTLDepthStencilState
    private let groundIndices: MTLBuffer
    private let bodyIndices: MTLBuffer
    private let particles: MTLBuffer
    private let noise: MTLTexture
    private let emberIllumination: MTLTexture
    private lazy var defaultTerrain = SandTerrain()
    private var terrainRevisions = [Int](repeating: -1, count: 3)
    private var terrainInstances = [SandTerrain?](repeating: nil, count: 3)
    private var scene: MTLTexture!
    private var gas: MTLTexture!
    private var depth: MTLTexture!
    private var dimensions = SIMD2<Int>(0, 0)
    private let gate = DispatchSemaphore(value: 3)
    private var frameIndex = 0
    private var spawnHead = 0
    private var uploads:
        [(bodies: MTLBuffer, newParticles: MTLBuffer, terrain: MTLBuffer, melts: MTLBuffer)] = []

    init(shaderURL: URL, output: MTLPixelFormat = .bgra8Unorm) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw RenderFailure.unavailable("Metal GPU unavailable")
        }
        self.device = device
        self.queue = queue
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let evolve = library.makeFunction(name: "evolve") else {
            throw RenderFailure.unavailable("Missing particle kernel")
        }
        compute = try device.makeComputePipelineState(function: evolve)
        guard let gather = library.makeFunction(name: "gatherChunks"),
            let chunkIndices = device.makeBuffer(
                length: Self.capacity * MemoryLayout<UInt32>.stride, options: .storageModePrivate),
            let chunkArguments = device.makeBuffer(length: 16, options: .storageModePrivate)
        else {
            throw RenderFailure.unavailable("Chunk compaction allocation failed")
        }
        self.chunkIndices = chunkIndices
        self.chunkArguments = chunkArguments
        gatherChunks = try device.makeComputePipelineState(function: gather)

        func pipeline(
            _ vertex: String, _ fragment: String, format: MTLPixelFormat, blend: Int, depth: Bool = false
        ) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            if depth { d.depthAttachmentPixelFormat = .depth32Float }
            let color = d.colorAttachments[0]!
            color.isBlendingEnabled = blend != 0
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = blend == 2 ? .oneMinusSourceAlpha : .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        bodies = try pipeline("bodyVertex", "bodyFragment", format: .rgba16Float, blend: 0, depth: true)
        impactFlashes = try pipeline("impactFlashVertex", "impactFlashFragment", format: .rgba16Float, blend: 1, depth: true)
        chunks = try pipeline("chunkVertex", "chunkFragment", format: .rgba16Float, blend: 0, depth: true)
        material = try pipeline("particleVertex", "particleFragment", format: .rgba16Float, blend: 2)
        ground = try pipeline("sandVertex", "sandFragment", format: .rgba16Float, blend: 0, depth: true)
        emberGround = try pipeline("emberGroundVertex", "emberGroundFragment", format: .rgba16Float, blend: 1)
        // Same fixed world extent as the terrain. Command-queue order protects this GPU-only target.
        let lightDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: SandTerrain.resolution, height: SandTerrain.resolution, mipmapped: false)
        lightDescriptor.storageMode = .private
        lightDescriptor.usage = [.renderTarget, .shaderRead]
        guard let emberIllumination = device.makeTexture(descriptor: lightDescriptor) else {
            throw RenderFailure.unavailable("Ember light map allocation failed")
        }
        self.emberIllumination = emberIllumination
        composite = try pipeline("screenVertex", "compositeFragment", format: output, blend: 0)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let write = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RenderFailure.unavailable("Depth write state unavailable")
        }
        depthWrite = write
        depthDescriptor.isDepthWriteEnabled = false
        guard let read = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RenderFailure.unavailable("Depth read state unavailable")
        }
        depthRead = read
        // Share the 257×257 grid vertices across triangles instead of shading six copies per cell.
        var indices: [UInt32] = []
        indices.reserveCapacity(256 * 256 * 6)
        for z in 0..<256 {
            for x in 0..<256 {
                let base = UInt32(z * 257 + x)
                for corner: UInt32 in [0, 1, 257, 257, 1, 258] { indices.append(base + corner) }
            }
        }
        guard
            let groundIndices = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw RenderFailure.unavailable("Terrain index allocation failed")
        }
        self.groundIndices = groundIndices
        var body: [UInt32] = []
        body.reserveCapacity(96 * 64 * 6)
        for y in 0..<64 {
            for x in 0..<96 {
                let base = UInt32(y * 97 + x)
                for corner: UInt32 in [0, 1, 97, 97, 1, 98] { body.append(base + corner) }
            }
        }
        guard
            let bodyIndices = device.makeBuffer(
                bytes: body,
                length: body.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw RenderFailure.unavailable("Body index allocation failed")
        }
        self.bodyIndices = bodyIndices
        guard
            let particles = device.makeBuffer(
                length: Self.capacity * MemoryLayout<ParticleGPU>.stride, options: .storageModePrivate)
        else {
            throw RenderFailure.unavailable("Particle buffer allocation failed")
        }
        self.particles = particles
        for _ in 0..<3 {
            guard
                let bodies = device.makeBuffer(
                    length: 20 * MemoryLayout<BodyGPU>.stride, options: .storageModeShared),
                let newParticles = device.makeBuffer(
                    length: 4096 * MemoryLayout<ParticleGPU>.stride, options: .storageModeShared),
                let melts = device.makeBuffer(
                    length: 16 * MemoryLayout<MeltPool>.stride, options: .storageModeShared),
                let terrain = device.makeBuffer(
                    length: SandTerrain.resolution * SandTerrain.resolution
                        * MemoryLayout<SIMD4<Float>>.stride,
                    options: .storageModeShared)
            else {
                throw RenderFailure.unavailable("Upload allocation failed")
            }
            uploads.append((bodies, newParticles, terrain, melts))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 128, height: 128, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let noise = device.makeTexture(descriptor: descriptor) else {
            throw RenderFailure.unavailable("Noise allocation failed")
        }
        self.noise = noise
        let values = (0..<16384).map { UInt8(hash(Double($0) * 1.371) * 255) }
        values.withUnsafeBytes { ptr in
            noise.replace(
                region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0, withBytes: ptr.baseAddress!,
                bytesPerRow: 128)
        }
        guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw RenderFailure.unavailable("Initialization command failed")
        }
        blit.fill(buffer: particles, range: 0..<particles.length, value: 0)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if command.status == .error {
            throw command.error ?? RenderFailure.unavailable("Particle buffer clear failed")
        }
    }

    private func resize(width: Int, height: Int) throws {
        if dimensions == SIMD2(width, height) { return }
        func texture(_ width: Int, _ height: Int, format: MTLPixelFormat = .rgba16Float) throws -> MTLTexture
        {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false)
            d.storageMode = .private
            d.usage = [.renderTarget, .shaderRead]
            guard let result = device.makeTexture(descriptor: d) else {
                throw RenderFailure.unavailable("Render target allocation failed")
            }
            return result
        }
        scene = try texture(width, height)
        gas = try texture(max(1, width / 2), max(1, height / 2))
        depth = try texture(width, height, format: .depth32Float)
        dimensions = SIMD2(width, height)
    }

    /// Encodes persistent sandy terrain, XYZ bodies/debris, vapor and HDR tone mapping.
    /// At most three frames own upload buffers; completion returns each slot before reuse.
    @discardableResult
    func render(
        frame: SimulationFrame, time: Float, delta: Float, brightness: Float,
        fade: Float, fill: Bool, output: MTLTexture, drawable: CAMetalDrawable? = nil, reset: Bool = false
    ) throws -> MTLCommandBuffer {
        guard frame.bodies.count <= 20, frame.newParticles.count <= 4096 else {
            throw RenderFailure.unavailable("Simulation capacity exceeded")
        }
        gate.wait()
        var committed = false
        defer { if !committed { gate.signal() } }
        try resize(width: output.width, height: output.height)
        let slot = frameIndex % 3
        let upload = uploads[slot]
        frameIndex += 1
        let terrain = frame.terrain ?? defaultTerrain
        // Each shared snapshot is protected by the same three-frame gate as the other uploads.
        // Copy only when that slot has not seen this terrain revision; resize never resets the field.
        if terrainInstances[slot] !== terrain || terrainRevisions[slot] != terrain.revision {
            terrain.cells.withUnsafeBytes { bytes in
                upload.terrain.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
            }
            terrainInstances[slot] = terrain
            terrainRevisions[slot] = terrain.revision
        }
        frame.bodies.withUnsafeBytes {
            if let p = $0.baseAddress, !$0.isEmpty {
                upload.bodies.contents().copyMemory(from: p, byteCount: $0.count)
            }
        }
        frame.newParticles.withUnsafeBytes {
            if let p = $0.baseAddress, !$0.isEmpty {
                upload.newParticles.contents().copyMemory(from: p, byteCount: $0.count)
            }
        }
        terrain.meltPools.withUnsafeBytes {
            if let p = $0.baseAddress, !$0.isEmpty {
                upload.melts.contents().copyMemory(from: p, byteCount: $0.count)
            }
        }
        let shake = SceneCamera.shake(for: frame.bodies)
        var uniforms = FrameUniformsGPU(
            viewport: SIMD4(
                Float(output.width), Float(output.height), Float(output.width) / Float(output.height), time),
            controls: SIMD4(delta, brightness, shake.x, shake.y),
            counts: SIMD4(
                UInt32(Self.capacity), UInt32(frame.newParticles.count), UInt32(spawnHead),
                UInt32(frame.bodies.count)),
            options: SIMD4(fade, fill ? 1 : 0, reset ? 1 : 0, 0),
            thermal: SIMD4(
                UInt32(terrain.meltPools.count),
                UInt32(
                    frame.bodies.filter { $0.impactEffects.x > 0 && $0.shape.z > 0 && $0.shape.z < 1.6 }.count
                ), UInt32(frame.bodies.filter {
                    $0.shape.z < 0 && $0.position.w > 0
                        && simd_length(SIMD3($0.flight.x, $0.flight.y, $0.flight.z)) > 0.5
                }.count), 0))
        spawnHead = (spawnHead + frame.newParticles.count) % Self.capacity
        guard let command = queue.makeCommandBuffer(), let clear = command.makeBlitCommandEncoder() else {
            throw RenderFailure.unavailable("Frame command failed")
        }
        command.label = "Noctiluca simulation + HDR"
        clear.fill(buffer: chunkArguments, range: 0..<16, value: 0)
        clear.endEncoding()
        guard let kernel = command.makeComputeCommandEncoder() else {
            throw RenderFailure.unavailable("Simulation encoder failed")
        }
        kernel.setComputePipelineState(compute)
        kernel.setBuffer(particles, offset: 0, index: 0)
        kernel.setBuffer(upload.newParticles, offset: 0, index: 1)
        kernel.setBytes(&uniforms, length: MemoryLayout<FrameUniformsGPU>.stride, index: 2)
        kernel.setBuffer(upload.bodies, offset: 0, index: 3)
        kernel.setBuffer(upload.terrain, offset: 0, index: 4)
        kernel.dispatchThreads(
            MTLSize(width: Self.capacity, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, compute.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        kernel.endEncoding()
        guard let gather = command.makeComputeCommandEncoder() else {
            throw RenderFailure.unavailable("Chunk encoder failed")
        }
        gather.setComputePipelineState(gatherChunks)
        gather.setBuffer(particles, offset: 0, index: 0)
        gather.setBuffer(chunkIndices, offset: 0, index: 1)
        gather.setBuffer(chunkArguments, offset: 0, index: 2)
        gather.setBytes(&uniforms, length: MemoryLayout<FrameUniformsGPU>.stride, index: 3)
        gather.dispatchThreads(
            MTLSize(width: Self.capacity, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, gatherChunks.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        gather.endEncoding()

        func pass(_ target: MTLTexture, depth: MTLTexture? = nil) throws -> MTLRenderCommandEncoder {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = target
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].storeAction = .store
            d.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            if let depth {
                d.depthAttachment.texture = depth
                d.depthAttachment.loadAction = .clear
                d.depthAttachment.storeAction = .store
                d.depthAttachment.clearDepth = 1
            }
            guard let encoder = command.makeRenderCommandEncoder(descriptor: d) else {
                throw RenderFailure.unavailable("Render encoder failed")
            }
            encoder.setFragmentTexture(noise, index: 4)
            encoder.setVertexTexture(noise, index: 4)
            encoder.setVertexBuffer(upload.terrain, offset: 0, index: 2)
            encoder.setFragmentBuffer(upload.terrain, offset: 0, index: 2)
            encoder.setFragmentBuffer(upload.melts, offset: 0, index: 3)
            return encoder
        }

        func geometry(_ target: MTLTexture, depth: MTLTexture) throws {
            var camera = uniforms
            let encoder = try pass(target, depth: depth)
            encoder.setVertexBuffer(upload.bodies, offset: 0, index: 0)
            encoder.setVertexBytes(&camera, length: MemoryLayout<FrameUniformsGPU>.stride, index: 1)
            encoder.setFragmentBytes(&camera, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
            encoder.setFragmentTexture(emberIllumination, index: 5)
            do {
                encoder.setDepthStencilState(depthWrite)
                encoder.setRenderPipelineState(ground)
                encoder.setFragmentBuffer(upload.bodies, offset: 0, index: 1)
                // Perspective spacing resolves near crater rims without a visible rectangular lattice.
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: 256 * 256 * 6, indexType: .uint32,
                    indexBuffer: groundIndices, indexBufferOffset: 0)
            }
            if !frame.bodies.isEmpty {
                encoder.setDepthStencilState(depthWrite)
                encoder.setRenderPipelineState(bodies)
                encoder.setFrontFacing(.counterClockwise)
                encoder.setCullMode(.none)
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: 96 * 64 * 6, indexType: .uint32,
                    indexBuffer: bodyIndices, indexBufferOffset: 0, instanceCount: frame.bodies.count)
            }
            encoder.setDepthStencilState(depthWrite)
            encoder.setRenderPipelineState(chunks)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBuffer(chunkIndices, offset: 0, index: 3)
            encoder.drawPrimitives(type: .triangle, indirectBuffer: chunkArguments, indirectBufferOffset: 0)
            if !frame.bodies.isEmpty {
                // All opaque meshes write depth before the impact flashes.
                encoder.setVertexBuffer(upload.bodies, offset: 0, index: 0)
                encoder.setDepthStencilState(depthRead)
                encoder.setRenderPipelineState(impactFlashes)
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: frame.bodies.count)
            }
            encoder.endEncoding()
        }

        func vapor(_ target: MTLTexture, depth: MTLTexture) throws {
            var camera = uniforms
            let encoder = try pass(target)
            encoder.setRenderPipelineState(material)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBytes(&camera, length: MemoryLayout<FrameUniformsGPU>.stride, index: 1)
            encoder.setFragmentBytes(&camera, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
            encoder.setFragmentTexture(depth, index: 3)
            encoder.setFragmentBuffer(upload.bodies, offset: 0, index: 1)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Self.capacity)
            encoder.endEncoding()
        }

        // Rebuild only illumination each frame; persistent geometry remains in the height field.
        let lightEncoder = try pass(emberIllumination)
        var lightCamera = uniforms
        lightEncoder.setRenderPipelineState(emberGround)
        lightEncoder.setVertexBuffer(particles, offset: 0, index: 0)
        lightEncoder.setVertexBytes(&lightCamera, length: MemoryLayout<FrameUniformsGPU>.stride, index: 1)
        lightEncoder.drawPrimitives(
            type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Self.capacity)
        lightEncoder.endEncoding()
        try geometry(scene, depth: depth)
        try vapor(gas, depth: depth)
        let screen = try pass(output)
        screen.setRenderPipelineState(composite)
        screen.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
        screen.setFragmentTexture(scene, index: 0)
        screen.setFragmentTexture(gas, index: 1)
        screen.setFragmentTexture(depth, index: 3)
        screen.setFragmentBuffer(upload.bodies, offset: 0, index: 1)
        screen.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        screen.endEncoding()
        if let drawable { command.present(drawable) }
        let gate = self.gate
        let metrics = self.metrics
        command.addCompletedHandler { buffer in
            metrics.record(buffer)
            gate.signal()
        }
        command.commit()
        committed = true
        return command
    }
}
