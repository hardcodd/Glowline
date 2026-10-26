import Foundation
import MetalKit

struct GPUFrame {
    var viewport: SIMD4<Float>
    var controls: SIMD4<Float>
    var counts: SIMD4<UInt32>
    var options: SIMD4<Float>
}

enum RenderFailure: Error { case unavailable(String) }

/// Completion timestamps measure GPU work, while host frame intervals measure visible pacing separately.
final class FrameMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    private var failures = 0
    func record(_ buffer: MTLCommandBuffer) {
        lock.lock(); defer { lock.unlock() }
        if buffer.status == .error { failures += 1 }
        let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
        if ms > 0 { times.append(ms) }
        if times.count > 1200 { times.removeFirst(times.count - 1200) }
    }
    func snapshot() -> (median: Double, p95: Double, max: Double, errors: Int, samples: Int) {
        lock.lock(); defer { lock.unlock() }
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0, failures, 0) }
        return (sorted[sorted.count/2], sorted[min(sorted.count-1, Int(Double(sorted.count)*0.95))], sorted.last!, failures, sorted.count)
    }
}

/// A reusable native renderer: no window, browser, serial controller or Glowline preferences are owned here.
final class MetalRenderer {
    static let capacity = 32768
    let device: MTLDevice
    let metrics = FrameMetrics()
    private let queue: MTLCommandQueue
    private let compute: MTLComputePipelineState
    private let solar: MTLRenderPipelineState
    private let halos: MTLRenderPipelineState
    private let material: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private let particles: MTLBuffer
    private let noise: MTLTexture
    private var scene: MTLTexture!
    private var gas: MTLTexture!
    private var dimensions = SIMD2<Int>(0, 0)
    private let gate = DispatchSemaphore(value: 3)
    private var frameIndex = 0
    private var spawnHead = 0
    private var uploads: [(suns: MTLBuffer, spawns: MTLBuffer)] = []

    init(shaderURL: URL, output: MTLPixelFormat = .bgra8Unorm) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw RenderFailure.unavailable("Metal GPU unavailable")
        }
        self.device = device; self.queue = queue
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let evolve = library.makeFunction(name: "evolve") else { throw RenderFailure.unavailable("Missing particle kernel") }
        compute = try device.makeComputePipelineState(function: evolve)

        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat, blend: Int) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            let color = d.colorAttachments[0]!
            color.isBlendingEnabled = blend != 0
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = blend == 2 ? .oneMinusSourceAlpha : .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        solar = try pipeline("starVertex", "starFragment", format: .rgba16Float, blend: 1)
        halos = try pipeline("haloVertex", "haloFragment", format: .rgba16Float, blend: 1)
        material = try pipeline("particleVertex", "particleFragment", format: .rgba16Float, blend: 2)
        composite = try pipeline("screenVertex", "compositeFragment", format: output, blend: 0)
        guard let particles = device.makeBuffer(length: Self.capacity * MemoryLayout<Particle>.stride, options: .storageModePrivate) else {
            throw RenderFailure.unavailable("Particle allocation failed")
        }
        self.particles = particles
        for _ in 0..<3 {
            guard let suns = device.makeBuffer(length: 20 * MemoryLayout<SunGPU>.stride, options: .storageModeShared),
                  let spawns = device.makeBuffer(length: 4096 * MemoryLayout<Particle>.stride, options: .storageModeShared) else {
                throw RenderFailure.unavailable("Upload allocation failed")
            }
            uploads.append((suns, spawns))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 128, height: 128, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let noise = device.makeTexture(descriptor: descriptor) else { throw RenderFailure.unavailable("Noise allocation failed") }
        self.noise = noise
        let values = (0..<16384).map { UInt8(hash(Double($0) * 1.371) * 255) }
        values.withUnsafeBytes { ptr in
            noise.replace(region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: 128)
        }
        guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw RenderFailure.unavailable("Initialization command failed")
        }
        blit.fill(buffer: particles, range: 0..<particles.length, value: 0)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if command.status == .error { throw command.error ?? RenderFailure.unavailable("Particle clear failed") }
    }

    private func resize(width: Int, height: Int) throws {
        if dimensions == SIMD2(width, height) { return }
        func texture(_ width: Int, _ height: Int) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            d.storageMode = .private; d.usage = [.renderTarget, .shaderRead]
            guard let result = device.makeTexture(descriptor: d) else { throw RenderFailure.unavailable("Render target allocation failed") }
            return result
        }
        scene = try texture(width, height)
        gas = try texture(max(1,width/2), max(1,height/2))
        dimensions = SIMD2(width, height)
    }

    /// Encodes bounded simulation, detailed suns, half-resolution vapor, then HDR tone mapping.
    /// At most three frames own upload buffers; completion returns each slot before reuse.
    @discardableResult
    func render(frame: SimulationFrame, time: Float, delta: Float, brightness: Float,
                fade: Float, fill: Bool, output: MTLTexture, drawable: CAMetalDrawable? = nil, reset: Bool = false) throws -> MTLCommandBuffer {
        guard frame.suns.count <= 20, frame.spawns.count <= 4096 else { throw RenderFailure.unavailable("Simulation capacity exceeded") }
        gate.wait()
        var committed = false
        defer { if !committed { gate.signal() } }
        try resize(width: output.width, height: output.height)
        let upload = uploads[frameIndex % 3]
        frameIndex += 1
        frame.suns.withUnsafeBytes { if let p = $0.baseAddress, !$0.isEmpty { upload.suns.contents().copyMemory(from: p, byteCount: $0.count) } }
        frame.spawns.withUnsafeBytes { if let p = $0.baseAddress, !$0.isEmpty { upload.spawns.contents().copyMemory(from: p, byteCount: $0.count) } }
        var uniforms = GPUFrame(viewport: SIMD4(Float(output.width),Float(output.height),Float(output.width)/Float(output.height),time),
            controls: SIMD4(delta,brightness,0,0),
            counts: SIMD4(UInt32(Self.capacity),UInt32(frame.spawns.count),UInt32(spawnHead),UInt32(frame.suns.count)),
            options: SIMD4(fade,fill ? 1 : 0,reset ? 1 : 0,0))
        spawnHead = (spawnHead + frame.spawns.count) % Self.capacity
        guard let command = queue.makeCommandBuffer(), let kernel = command.makeComputeCommandEncoder() else {
            throw RenderFailure.unavailable("Frame command failed")
        }
        command.label = "Noctiluca simulation + HDR"
        kernel.setComputePipelineState(compute)
        kernel.setBuffer(particles, offset: 0, index: 0); kernel.setBuffer(upload.spawns, offset: 0, index: 1)
        kernel.setBytes(&uniforms, length: MemoryLayout<GPUFrame>.stride, index: 2)
        kernel.setBuffer(upload.suns, offset: 0, index: 3)
        kernel.dispatchThreads(MTLSize(width: Self.capacity,height: 1,depth: 1), threadsPerThreadgroup: MTLSize(width: min(256,compute.maxTotalThreadsPerThreadgroup),height: 1,depth: 1))
        kernel.endEncoding()

        func pass(_ target: MTLTexture) throws -> MTLRenderCommandEncoder {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = target
            d.colorAttachments[0].loadAction = .clear; d.colorAttachments[0].storeAction = .store
            d.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: d) else { throw RenderFailure.unavailable("Render encoder failed") }
            encoder.setFragmentTexture(noise,index: 4)
            return encoder
        }
        let stars = try pass(scene)
        stars.setVertexBuffer(upload.suns,offset: 0,index: 0)
        stars.setVertexBytes(&uniforms,length: MemoryLayout<GPUFrame>.stride,index: 1)
        if !frame.suns.isEmpty {
            stars.setRenderPipelineState(halos)
            stars.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 6,instanceCount: frame.suns.count)
            stars.setRenderPipelineState(solar)
            stars.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 6,instanceCount: frame.suns.count)
        }
        stars.endEncoding()
        let vapor = try pass(gas)
        vapor.setRenderPipelineState(material)
        vapor.setVertexBuffer(particles,offset: 0,index: 0)
        vapor.setVertexBytes(&uniforms,length: MemoryLayout<GPUFrame>.stride,index: 1)
        vapor.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 6,instanceCount: Self.capacity)
        vapor.endEncoding()
        let screen = try pass(output)
        screen.setRenderPipelineState(composite)
        screen.setFragmentBytes(&uniforms,length: MemoryLayout<GPUFrame>.stride,index: 0)
        screen.setFragmentTexture(scene,index: 0); screen.setFragmentTexture(gas,index: 1)
        screen.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 6)
        screen.endEncoding()
        if let drawable { command.present(drawable) }
        let gate = self.gate, metrics = self.metrics
        command.addCompletedHandler { buffer in metrics.record(buffer); gate.signal() }
        command.commit(); committed = true
        return command
    }
}
