import Foundation
import MetalKit

/// Actual Metal contracts: rigid spin/contact, opaque depth, cooling and persistent terrain.
@main struct SandGPUContracts {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw RenderFailure.unavailable("Metal GPU required")
        }
        let url = URL(fileURLWithPath: "Resources/Noctiluca.metal")
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let kernel = try device.makeComputePipelineState(function: library.makeFunction(name: "evolve")!)
        let terrain = SandTerrain()
        terrain.strike(at: SIMD2(0, -5), radius: 1, direction: SIMD2(1, 0), seed: 1)
        terrain.advance(delta: 1)
        let ground = terrain.cells.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)!
        }
        var particle = ParticleGPU(
            position: SIMD4(0, 0.8, 0, 0), life: SIMD4(0.035, 0, 6, 7),
            color: SIMD4(1, 0.5, 0.1, 3), owner: SIMD4(1, 1, -5, 0), angular: SIMD4(3, 5, 2, 0))
        let state = device.makeBuffer(bytes: &particle, length: MemoryLayout<ParticleGPU>.stride)!
        let empty = device.makeBuffer(length: MemoryLayout<BodyGPU>.stride)!
        func step(_ delta: Float) throws -> ParticleGPU {
            var frame = FrameUniformsGPU(
                viewport: SIMD4(320, 180, 16 / 9, 0), controls: SIMD4(delta, 1, 0, 0),
                counts: SIMD4(1, 0, 0, 0), options: .zero)
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(kernel)
            encoder.setBuffer(state, offset: 0, index: 0)
            encoder.setBuffer(empty, offset: 0, index: 1)
            encoder.setBytes(&frame, length: MemoryLayout<FrameUniformsGPU>.stride, index: 2)
            encoder.setBuffer(empty, offset: 0, index: 3)
            encoder.setBuffer(ground, offset: 0, index: 4)
            encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed)
            return state.contents().load(as: ParticleGPU.self)
        }
        let spinning = try step(1 / 60)
        precondition(
            spinning.orientation != particle.orientation
                && abs(simd_length(spinning.orientation) - 1) < 0.00001,
            "Flying rocks must tumble with normalized independent orientation")
        let spinPause = try step(0)
        precondition(spinPause.orientation == spinning.orientation, "Pause must freeze angular motion")
        var landed: ParticleGPU?
        var sawBounce = false
        for _ in 0..<180 {
            let result = try step(1 / 60)
            if result.owner.y == 1.5 { sawBounce = true }
            if result.owner.y >= 2 {
                landed = result
                break
            }
        }
        precondition(sawBounce, "A falling chunk must lose energy in a short bounce before settling")
        precondition(landed != nil, "Fragment must land in the crater")
        let landing = landed!
        precondition(
            landing.angular.w > 0 && landing.angular.w < 1,
            "Landing must retain flight cooling instead of reheating the fragment")
        let landingPoint = SIMD2(landing.position.x, landing.owner.z)
        precondition(
            landing.position.y > terrain.height(at: landingPoint)
                && landing.position.y < terrain.height(at: landingPoint) + landing.life.x * 1.8)
        var raisedGround = terrain.cells
        for i in raisedGround.indices { raisedGround[i].x += 0.08 }
        raisedGround.withUnsafeBytes {
            ground.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        let coveredRock = try step(1 / 60)
        precondition(
            coveredRock.position == landing.position && coveredRock.orientation == landing.orientation,
            "Deposited ground must cover a resting rock instead of pulling it up like a buoy")
        terrain.cells.withUnsafeBytes {
            ground.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        let paused = try step(0)
        precondition(paused.position == landing.position && paused.life == coveredRock.life)
        for _ in 0..<30 { _ = try step(1 / 60) }
        let settledRock = try step(0)
        for _ in 0..<60 { _ = try step(1 / 60) }
        let warm = try step(0)
        precondition(
            warm.life.y < warm.life.z && warm.position == settledRock.position
                && warm.orientation == settledRock.orientation,
            "Settled fragments must retain their rigid pose while emission cools")
        var droppedGround = terrain.cells
        for i in droppedGround.indices { droppedGround[i].x -= 0.2 }
        droppedGround.withUnsafeBytes {
            ground.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        let released = try step(1 / 60)
        precondition(
            released.position.y < warm.position.y && released.position.y > warm.position.y - 0.01,
            "New excavation must release a rock under gravity instead of dragging it down with the surface")
        var savedWarm = warm
        withUnsafeBytes(of: &savedWarm) {
            state.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        terrain.cells.withUnsafeBytes {
            ground.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        for _ in 0..<90 { _ = try step(1 / 60) }
        let cold = try step(0)
        precondition(
            cold.life.y < cold.life.z && cold.orientation == settledRock.orientation,
            "The rigid-body anchor stays fixed while its material fractures into crumbs")
        for _ in 0..<600 { _ = try step(1 / 60) }
        let expiredRock = try step(0)
        precondition(expiredRock.life.y >= cold.life.z, "Cold rocks must retain bounded residence")
        // Contact must remain bounded for fast oblique shards at low/high display cadence and after a long frame.
        for cadence: Float in [1 / 30, 1 / 72, 1 / 144, 0.1] {
            for seed in 0..<8 {
                var shard = ParticleGPU(
                    position: SIMD4(0, 0.8, Float(seed - 4) * 0.7, -2 - Float(seed)),
                    life: SIMD4(0.025 + Float(seed) * 0.055, 0, 6, Float(seed) * 7.13),
                    color: SIMD4(1, 0.5, 0.1, 3), owner: SIMD4(1, 1, -5, Float(seed - 3) * 0.4),
                    angular: SIMD4(Float(seed) + 1, 5, -3, 1))
                withUnsafeBytes(of: &shard) {
                    state.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
                }
                var result = shard
                for _ in 0..<Int(4 / cadence) {
                    result = try step(cadence)
                    precondition(
                        result.position.x.isFinite && result.position.y.isFinite && result.owner.z.isFinite)
                    precondition(abs(simd_length(result.orientation) - 1) < 0.0001)
                    precondition(
                        result.position.y > terrain.height(at: SIMD2(result.position.x, result.owner.z))
                            - result.life.x,
                        "A fast shard must not tunnel through the terrain")
                }
                precondition(result.owner.y >= 2, "Dry contact must settle at every tested cadence")
                let pose = result.position
                let rotation = result.orientation
                for _ in 0..<Int(0.5 / cadence) { result = try step(cadence) }
                precondition(
                    result.position == pose && result.orientation == rotation,
                    "Landed shards must not creep or jitter after settling")
            }
        }
        print("PASS: 32 rigid-contact trajectories at 30/72/144 Hz and 100 ms frames")
        var grain = ParticleGPU(
            position: SIMD4(0, 0.8, 0.5, 0.4), life: SIMD4(0.015, 0, 3.2, 11),
            color: SIMD4(0.57, 0.59, 0.63, 7), owner: SIMD4(2, 1, -5, 0.3))
        withUnsafeBytes(of: &grain) {
            state.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        var settledGrain: ParticleGPU?
        for _ in 0..<180 {
            let result = try step(1 / 60)
            if result.owner.y >= 2 {
                settledGrain = result
                break
            }
        }
        precondition(
            settledGrain != nil && settledGrain!.position.x > 0,
            "Solid regolith grains must follow ballistic arcs and settle on terrain")
        let grainPause = try step(0)
        precondition(grainPause.position == settledGrain!.position && grainPause.life == settledGrain!.life)
        for _ in 0..<40 { _ = try step(1 / 60) }
        let fadedGrain = try step(0)
        precondition(
            fadedGrain.life.y >= 0.45, "Settled grains must fade without acquiring a hot cooling phase")
        var tailSpark = ParticleGPU(
            position: SIMD4(0, 3, 0, -0.08), life: SIMD4(0.01, 0, 4, 9),
            color: SIMD4(1, 0.6, 0.1, 1), owner: SIMD4(1, -1, -5, 0))
        withUnsafeBytes(of: &tailSpark) {
            state.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        for _ in 0..<120 { _ = try step(1 / 60) }
        let trailingSpark = try step(0)
        precondition(
            trailingSpark.position.w > -0.08 && trailingSpark.position.y > 2.84,
            "Tail sparks must decelerate in the wake instead of accelerating down past the body")

        // Render the actual opaque mesh pipeline against a clear target and a rear rock.
        let rockDescriptor = MTLRenderPipelineDescriptor()
        rockDescriptor.vertexFunction = library.makeFunction(name: "chunkVertex")
        rockDescriptor.fragmentFunction = library.makeFunction(name: "chunkFragment")
        rockDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        rockDescriptor.depthAttachmentPixelFormat = .depth32Float
        let rockPipeline = try device.makeRenderPipelineState(descriptor: rockDescriptor)
        let rockTargetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 320, height: 180, mipmapped: false)
        rockTargetDescriptor.storageMode = .shared
        rockTargetDescriptor.usage = [.renderTarget]
        let rockTarget = device.makeTexture(descriptor: rockTargetDescriptor)!
        let rockDepthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: 320, height: 180, mipmapped: false)
        rockDepthDescriptor.storageMode = .private
        rockDepthDescriptor.usage = [.renderTarget, .shaderRead]
        let rockDepth = device.makeTexture(descriptor: rockDepthDescriptor)!
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        let rockDepthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
        let noiseDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: 1, height: 1, mipmapped: false)
        noiseDescriptor.storageMode = .shared
        noiseDescriptor.usage = [.shaderRead]
        let rockNoise = device.makeTexture(descriptor: noiseDescriptor)!
        var noiseValue: Float = 0.5
        rockNoise.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &noiseValue, bytesPerRow: 4)
        func rockPixels(_ rocks: [ParticleGPU]) throws -> [UInt16] {
            let buffer = rocks.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)!
            }
            var frame = FrameUniformsGPU(
                viewport: SIMD4(320, 180, 16 / 9, 0), controls: SIMD4(0, 1, 0, 0),
                counts: .zero, options: SIMD4(0, 1, 0, 0))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = rockTarget
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            pass.depthAttachment.texture = rockDepth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(rockPipeline)
            encoder.setDepthStencilState(rockDepthState)
            let indices = (0..<UInt32(rocks.count)).map { $0 }
            let indexBuffer = indices.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)!
            }
            encoder.setVertexBuffer(indexBuffer, offset: 0, index: 3)
            encoder.setVertexBuffer(ground, offset: 0, index: 2)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniformsGPU>.stride, index: 1)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
            encoder.setFragmentBuffer(empty, offset: 0, index: 1)
            encoder.setFragmentBuffer(empty, offset: 0, index: 3)
            encoder.setFragmentBuffer(ground, offset: 0, index: 2)
            encoder.setFragmentTexture(rockNoise, index: 4)
            encoder.setFragmentTexture(rockNoise, index: 5)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0, vertexCount: 240, instanceCount: rocks.count)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed)
            var result = [UInt16](repeating: 0, count: 320 * 180 * 4)
            rockTarget.getBytes(
                &result, bytesPerRow: 320 * 8, from: MTLRegionMake2D(0, 0, 320, 180), mipmapLevel: 0)
            return result
        }
        var frontRock = ParticleGPU(
            position: SIMD4(0, 0.42, 0, 0), life: SIMD4(0.6, 0, 12, 7),
            color: SIMD4(1, 0.3, 0.1, 3), owner: SIMD4(1, 2, -5, 0))
        var rearRock = frontRock
        rearRock.owner.z = -6
        rearRock.life.x = 0.3
        rearRock.color = SIMD4(0, 1, 0, 3)
        let opaque = try rockPixels([frontRock])
        precondition(
            opaque.allSatisfy { $0 & 0x7c00 != 0x7c00 },
            "Opaque rock shading must keep all HDR channels finite")
        precondition(
            stride(from: 3, to: opaque.count, by: 4).filter { opaque[$0] == 0x3c00 }.count > 100,
            "A volumetric fragment must cover pixels with exactly opaque alpha")
        precondition(
            stride(from: 3, to: opaque.count, by: 4).allSatisfy { opaque[$0] == 0 || opaque[$0] == 0x3c00 })
        let occluded = try rockPixels([frontRock, rearRock])
        precondition(opaque == occluded, "Front rock depth must fully occlude a bright rear fragment")
        frontRock.life.y = 4
        let coldOpaque = try rockPixels([frontRock])
        let solidPixels = stride(from: 3, to: opaque.count, by: 4).filter { opaque[$0] == 0x3c00 }.count
        let ashPixels = stride(from: 3, to: coldOpaque.count, by: 4).filter { coldOpaque[$0] == 0x3c00 }.count
        print("Rock silhouette pixels:", solidPixels, "ash:", ashPixels)
        precondition(
            ashPixels < solidPixels / 3 && ashPixels > 0,
            "A cooled rock must fracture and erode into opaque crumbs, never retain a full timed silhouette")
        precondition(
            stride(from: 3, to: coldOpaque.count, by: 4).allSatisfy {
                coldOpaque[$0] == 0 || coldOpaque[$0] == 0x3c00
            },
            "Crumbling removes material cells without alpha-fading the rock")
        precondition(coldOpaque != opaque, "Cooling must extinguish emission instead of fading geometry")

        // Dense vapor must attenuate rear geometry, otherwise rocks look pasted over illuminated smoke.
        let compositeDescriptor = MTLRenderPipelineDescriptor()
        compositeDescriptor.vertexFunction = library.makeFunction(name: "screenVertex")
        compositeDescriptor.fragmentFunction = library.makeFunction(name: "compositeFragment")
        compositeDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let compositePipeline = try device.makeRenderPipelineState(descriptor: compositeDescriptor)
        let pixelDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 1, height: 1, mipmapped: false)
        pixelDescriptor.storageMode = .shared
        pixelDescriptor.usage = [.renderTarget, .shaderRead]
        let litScene = device.makeTexture(descriptor: pixelDescriptor)!
        let vapor = device.makeTexture(descriptor: pixelDescriptor)!
        let composed = device.makeTexture(descriptor: pixelDescriptor)!
        var litValues: [Float16] = [1, 1, 1, 1]
        var vaporValues: [Float16] = [0.1, 0.1, 0.1, 0.8]
        litScene.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &litValues, bytesPerRow: 8)
        vapor.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &vaporValues, bytesPerRow: 8)
        let compositePass = MTLRenderPassDescriptor()
        compositePass.colorAttachments[0].texture = composed
        compositePass.colorAttachments[0].loadAction = .clear
        compositePass.colorAttachments[0].storeAction = .store
        let compositeCommand = queue.makeCommandBuffer()!
        let compositeEncoder = compositeCommand.makeRenderCommandEncoder(descriptor: compositePass)!
        compositeEncoder.setRenderPipelineState(compositePipeline)
        var compositeFrame = FrameUniformsGPU(
            viewport: SIMD4(1, 1, 1, 0), controls: SIMD4(0, 1, 0, 0),
            counts: .zero, options: SIMD4(1, 1, 0, 0))
        compositeEncoder.setFragmentBytes(
            &compositeFrame, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
        compositeEncoder.setFragmentTexture(rockDepth, index: 3)
        compositeEncoder.setFragmentTexture(rockNoise, index: 4)
        compositeEncoder.setFragmentBuffer(empty, offset: 0, index: 1)
        compositeEncoder.setFragmentTexture(litScene, index: 0)
        compositeEncoder.setFragmentTexture(vapor, index: 1)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        compositeEncoder.endEncoding()
        compositeCommand.commit()
        compositeCommand.waitUntilCompleted()
        precondition(compositeCommand.status == .completed)
        var composedValues = [Float16](repeating: 0, count: 4)
        composed.getBytes(&composedValues, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        precondition(
            composedValues[0] > 0.2 && composedValues[0] < 0.4,
            "Vapor transmittance must attenuate rear scene light instead of only adding a glow")

        // A patterned scene separates genuine refraction (darkened displaced features) from additive glow.
        let lensDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 256, height: 144, mipmapped: false)
        lensDescriptor.storageMode = .shared
        lensDescriptor.usage = [.renderTarget, .shaderRead]
        let pattern = device.makeTexture(descriptor: lensDescriptor)!
        let lensOutput = device.makeTexture(descriptor: lensDescriptor)!
        var stripes = [Float16](repeating: 0, count: 256 * 144 * 4)
        for y in 0..<144 {
            for x in 0..<256 {
                let i = (y * 256 + x) * 4
                stripes[i] = (x / 4 + y / 4) % 2 == 0 ? 1 : 0.02
                stripes[i + 1] = Float16(Float(y) / 144)
                stripes[i + 2] = 0.15
                stripes[i + 3] = 1
            }
        }
        pattern.replace(
            region: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0, withBytes: &stripes, bytesPerRow: 256 * 8
        )
        let lensDepthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: 256, height: 144, mipmapped: false)
        lensDepthDescriptor.storageMode = .private
        lensDepthDescriptor.usage = [.renderTarget, .shaderRead]
        let lensDepth = device.makeTexture(descriptor: lensDepthDescriptor)!
        let clearVapor = device.makeTexture(descriptor: pixelDescriptor)!
        var clearValues = [Float16](repeating: 0, count: 4)
        clearVapor.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clearValues, bytesPerRow: 8)
        var shell = BodyGPU(
            position: .zero, color: SIMD4(0.9, 0.1, 0.4, 1),
            motion: SIMD4(-4.8, 0.3, 0, 7), cloud: .zero, shape: SIMD4(0, 0, 0.3, 0.1),
            spatial: SIMD4(0, 1.82, -4.8, 0.5), contact: SIMD4(0, 1.82, -4.8, 0),
            impactEffects: SIMD4(1, 0, 0, 0))
        func lensImage(_ event: BodyGPU, enabled: Bool = true, depthValue: Double = 1, fade: Float = 1)
            -> [Float16]
        {
            let command = queue.makeCommandBuffer()!
            let clearPass = MTLRenderPassDescriptor()
            clearPass.depthAttachment.texture = lensDepth
            clearPass.depthAttachment.loadAction = .clear
            clearPass.depthAttachment.storeAction = .store
            clearPass.depthAttachment.clearDepth = depthValue
            command.makeRenderCommandEncoder(descriptor: clearPass)!.endEncoding()
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = lensOutput
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            var frame = FrameUniformsGPU(
                viewport: SIMD4(256, 144, 256 / 144, 0), controls: SIMD4(0, 1, 0, 0),
                counts: SIMD4(0, 0, 0, 1), options: SIMD4(fade, 1, 0, 0),
                thermal: SIMD4(0, enabled ? 1 : 0, 0, 0))
            var event = event
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniformsGPU>.stride, index: 0)
            encoder.setFragmentBytes(&event, length: MemoryLayout<BodyGPU>.stride, index: 1)
            encoder.setFragmentTexture(pattern, index: 0)
            encoder.setFragmentTexture(clearVapor, index: 1)
            encoder.setFragmentTexture(lensDepth, index: 3)
            encoder.setFragmentTexture(rockNoise, index: 4)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed)
            var values = [Float16](repeating: 0, count: stripes.count)
            lensOutput.getBytes(
                &values, bytesPerRow: 256 * 8, from: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0)
            precondition(
                values.allSatisfy { $0.isFinite }, "Shells must remain finite at every ray/sphere boundary")
            return values
        }
        let plainPattern = lensImage(shell, enabled: false)
        let refracted = lensImage(shell)
        let displacedDark = stride(from: 0, to: refracted.count, by: 4).filter {
            refracted[$0] < plainPattern[$0] - 0.02
        }.count
        precondition(
            displacedDark > 50,
            "A pressure shell must displace scene features, not merely add a luminous ring")
        // Refraction must dominate self-emission: a dark background cannot reveal another glowing hoop.
        var darkPattern = [Float16](repeating: 0, count: stripes.count)
        pattern.replace(
            region: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0, withBytes: &darkPattern,
            bytesPerRow: 256 * 8)
        let darkShell = lensImage(shell)
        let luminousPeak = darkShell.enumerated().filter { $0.offset % 4 != 3 }.map { Float($0.element) }
            .max()!
        precondition(
            luminousPeak < 0.035, "Pressure must read as transparent refraction, not a self-lit ring")
        pattern.replace(
            region: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0, withBytes: &stripes, bytesPerRow: 256 * 8
        )
        var gradient = stripes
        for y in 0..<144 {
            for x in 0..<256 { gradient[(y * 256 + x) * 4] = Float16(Float(x) / 256) }
        }
        pattern.replace(
            region: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0, withBytes: &gradient,
            bytesPerRow: 256 * 8)
        let straight = lensImage(shell, enabled: false)
        let bent = lensImage(shell)
        let rightSide = (129..<210).map { Float(bent[(72 * 256 + $0) * 4] - straight[(72 * 256 + $0) * 4]) }
        fputs("Refraction phases: min \(rightSide.min()!), max \(rightSide.max()!)\n", stderr)
        precondition(
            rightSide.filter { $0 > 0.003 }.count > 3 && rightSide.filter { $0 < -0.003 }.count > 3,
            "The leading compression and trailing rarefaction must variation the scene in opposite directions"
        )
        pattern.replace(
            region: MTLRegionMake2D(0, 0, 256, 144), mipmapLevel: 0, withBytes: &stripes, bytesPerRow: 256 * 8
        )
        precondition(lensImage(shell) == refracted, "Paused lensing must be exactly stable")
        precondition(
            lensImage(shell, depthValue: 0.95) == plainPattern,
            "Opaque foreground must hide a pressure shell behind it")
        var drifting = shell
        drifting.spatial.x += 10
        drifting.cloud.x += 20
        precondition(lensImage(drifting) == refracted, "A shell must stay at the fixed 3D impact point")
        func affected(_ image: [Float16]) -> Int {
            stride(from: 0, to: image.count, by: 4).filter { abs(Float(image[$0] - plainPattern[$0])) > 0.01 }
                .count
        }
        var distant = shell
        distant.contact = SIMD4(0, 3.22, -9.6, 0)
        precondition(
            affected(lensImage(distant)) < affected(refracted) / 2,
            "An equally sized world-space shell must project smaller at greater depth")
        shell.shape.z = 1.6
        precondition(
            lensImage(shell) == plainPattern, "Expired shock shells must leave no distortion or light")
        shell.shape.z = 0.3
        shell.contact = SIMD4(0, 0.42, 0, 0)
        _ = lensImage(shell)
        precondition(
            lensImage(shell, fade: 0).enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 })
        print(
            "PASS: spherical shock refraction, opaque depth, fixed contact, perspective, pause, expiry and finite inside-shell rays"
        )

        let renderer = try MetalRenderer(shaderURL: url)
        func target(_ width: Int, _ height: Int) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            return renderer.device.makeTexture(descriptor: descriptor)!
        }
        func pixels(
            _ output: MTLTexture, time: Float, fade: Float = 1, bodies: [BodyGPU] = [],
            newParticles: [ParticleGPU] = [], delta: Float = 0, field: SandTerrain? = nil
        ) throws -> [UInt8] {
            let frame = SimulationFrame(bodies: bodies, newParticles: newParticles, terrain: field ?? terrain)
            let command = try renderer.render(
                frame: frame, time: time, delta: delta, brightness: 1, fade: fade, fill: true, output: output)
            command.waitUntilCompleted()
            precondition(command.status == .completed)
            var bytes = [UInt8](repeating: 0, count: output.width * output.height * 4)
            output.getBytes(
                &bytes, bytesPerRow: output.width * 4,
                from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0)
            return bytes
        }
        let output = target(860, 360)
        let first = try pixels(output, time: 0)
        let ambientPeak = stride(from: 0, to: first.count, by: 4).map {
            max(first[$0], first[$0 + 1], first[$0 + 2])
        }.max()!
        precondition(ambientPeak <= 2, "Unlit regolith must be almost invisible by default")
        var approaching = BodyGPU(
            position: SIMD4(0, 0, 0.08, 1), color: SIMD4(1, 0.3, 0.05, 1),
            motion: SIMD4(-5, -1, 1, 7), cloud: .zero, shape: SIMD4(0, 0, -1, 0.3),
            spatial: SIMD4(0, 1, -5, 0.4), contact: SIMD4(0, 0, -5, 1))
        let nearLight = try pixels(output, time: 0, bodies: [approaching])
        approaching.spatial.y = 8
        let farLight = try pixels(output, time: 0, bodies: [approaching])
        func groundEnergy(_ bytes: [UInt8]) -> Int {
            let start = output.width * (output.height * 4 / 5) * 4
            return stride(from: start, to: bytes.count, by: 4).reduce(0) {
                $0 + Int(bytes[$1]) + Int(bytes[$1 + 1]) + Int(bytes[$1 + 2])
            }
        }
        precondition(
            groundEnergy(nearLight) > groundEnergy(farLight) * 2,
            "Approaching objects must reveal the ground with local colored illumination")
        let later = try pixels(output, time: 100)
        precondition(first == later, "Unlit sand and craters must not animate or expire")
        _ = try pixels(target(640, 480), time: 101)
        let resized = try pixels(output, time: 102)
        precondition(resized == first, "Resize must preserve the complete terrain")
        let black = try pixels(output, time: 103, fade: 0)
        precondition(
            stride(from: 0, to: black.count, by: 4).allSatisfy {
                black[$0] == 0 && black[$0 + 1] == 0 && black[$0 + 2] == 0
            })
        let oldImpact = BodyGPU(
            position: SIMD4(0, 0, 0.2, 0), color: SIMD4(0.1, 1, 0.2, 1),
            motion: SIMD4(-5, 4, 1, 7), cloud: SIMD4(0, 0, 1, 0), shape: SIMD4(0, 0, 4, 0.3),
            spatial: SIMD4(0, 0.8, -5, 0.8), contact: SIMD4(0, 0, -5, 1))
        let extinguished = try pixels(output, time: 104, bodies: [oldImpact])
        let lingering = zip(extinguished, first).filter { abs(Int($0) - Int($1)) > 8 }.count
        precondition(
            lingering < 100, "A broken ground body must not leave its solar corona suspended over the crater")
        var flash = oldImpact
        flash.shape.z = 0.05
        flash.motion.y = 0.05
        let ordinaryBurst = try pixels(output, time: 0, bodies: [flash])
        flash.impactEffects.x = 1
        let bolideBurst = try pixels(output, time: 0, bodies: [flash])
        precondition(
            groundEnergy(bolideBurst) > groundEnergy(ordinaryBurst) * 12 / 10,
            "A rare high-energy impact must illuminate substantially more ground")
        var showerFlash = flash
        showerFlash.impactEffects = SIMD4(0, 1, 0, 0)
        showerFlash.shape.z = 0.25
        showerFlash.motion.y = 0.25
        let brightShower = try pixels(output, time: 0, bodies: [showerFlash])
        showerFlash.impactEffects.y = 0
        let plainShower = try pixels(output, time: 0, bodies: [showerFlash])
        func imageEnergy(_ bytes: [UInt8]) -> Int {
            stride(from: 0, to: bytes.count, by: 4).reduce(0) {
                $0 + Int(bytes[$1]) + Int(bytes[$1 + 1]) + Int(bytes[$1 + 2])
            }
        }
        precondition(
            imageEnergy(brightShower) > imageEnergy(plainShower) * 3,
            "Shower impacts must add a substantial colored expanding flash")
        var greenPixels = 0
        for index in stride(from: 0, to: brightShower.count, by: 4) {
            let green = Int(brightShower[index + 1])
            let red = Int(brightShower[index + 2])
            if green > 60 && green > red * 2 { greenPixels += 1 }
        }
        precondition(
            greenPixels > output.width * output.height / 100,
            "The flash must retain its colored area instead of becoming a white blink")
        showerFlash.impactEffects.y = 1
        showerFlash.shape.z = 3
        showerFlash.motion.y = 3
        let expiredShower = try pixels(output, time: 0, bodies: [showerFlash])
        precondition(zip(expiredShower, first).filter { abs(Int($0) - Int($1)) > 8 }.count < 200)

        var tremor = approaching
        tremor.shape.z = 0.10
        tremor.motion.y = 0.10
        let stillScene = try pixels(output, time: 0, bodies: [tremor])
        tremor.impactEffects.z = 1
        let movingScene = try pixels(output, time: 0, bodies: [tremor])
        precondition(
            movingScene != stillScene, "Strong ground impacts must visibly displace the composed scene")
        let pausedTremor = try pixels(output, time: 0, bodies: [tremor])
        precondition(movingScene == pausedTremor, "Paused tremors must preserve every rendered pixel")
        let darkTremor = try pixels(output, time: 0, fade: 0, bodies: [tremor])
        precondition(imageEnergy(darkTremor) == 0)
        flash.shape.z = 0.35
        flash.motion.y = 0.35
        let broadBlast = try pixels(output, time: 0, bodies: [flash])
        func edgeEnergy(_ bytes: [UInt8]) -> Int {
            var total = 0
            for y in 0..<output.height {
                for x in 0..<output.width
                where x < output.width / 12 || x >= output.width * 11 / 12
                    || y < output.height / 12 || y >= output.height * 11 / 12
                {
                    let i = (y * output.width + x) * 4
                    total += Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])
                }
            }
            return total
        }
        let brightArea = stride(from: 0, to: broadBlast.count, by: 4).filter {
            max(broadBlast[$0], broadBlast[$0 + 1], broadBlast[$0 + 2]) > 80
        }.count
        precondition(
            brightArea > output.width * output.height / 12,
            "Bolide light must occupy substantial screen area beyond a tiny white core")
        precondition(
            edgeEnergy(broadBlast) > edgeEnergy(ordinaryBurst) * 3,
            "The colored blast must reach screen-edge capture zones")
        flash.shape.z = 4
        flash.motion.y = 4
        let cooledFlash = try pixels(output, time: 0, bodies: [flash])
        precondition(
            zip(cooledFlash, first).filter { abs(Int($0) - Int($1)) > 8 }.count < 100,
            "Bolide flash must fade without leaving a luminous billboard")
        approaching.spatial.y = 1
        let beforeExcavation = try pixels(output, time: 0, bodies: [approaching])
        terrain.strike(at: SIMD2(0.5, -4), radius: 1, direction: SIMD2(0, 1), seed: 2)
        terrain.advance(delta: 0.15)
        let changed = try pixels(output, time: 0, bodies: [approaching])
        precondition(changed != beforeExcavation, "An illuminated new impact must change visible geometry")
        terrain.advance(delta: 1)
        let completed = try pixels(output, time: 0, bodies: [approaching])
        precondition(completed != changed, "GPU must display progressive crater formation")
        terrain.advance(delta: 8)
        let settled = try pixels(output, time: 0, bodies: [approaching])
        terrain.advance(delta: 100)
        let stable = try pixels(output, time: 0, bodies: [approaching])
        precondition(stable == settled, "Gravitationally settled excavation must remain fixed")
        let darkStable = try pixels(output, time: 206)
        let emberPoint = SIMD2<Float>(-1.5, -4)
        let ember = ParticleGPU(
            position: SIMD4(emberPoint.x, terrain.height(at: emberPoint) + 0.02, 0, 0),
            life: SIMD4(0.04, 0, 2.4, 7), color: SIMD4(1, 0.4, 0.05, 3), owner: SIMD4(1, 2, emberPoint.y, 0))
        let glowing = try pixels(output, time: 207, newParticles: [ember])
        let samplePoint = emberPoint + SIMD2(0.2, 0)
        let screen = SceneCamera.project(SIMD3(samplePoint.x, terrain.height(at: samplePoint), samplePoint.y))
        let px = Int(Float(output.width) / 2 + screen.x * Float(output.height))
        let py = Int(Float(output.height) / 2 - screen.y * Float(output.height))
        let sampleIndex = (py * output.width + px) * 4
        precondition(
            Int(glowing[sampleIndex + 2]) > Int(darkStable[sampleIndex + 2]) + 5,
            "A landed ember must illuminate terrain beyond its own visible silhouette")
        let extinguishedEmber = try pixels(output, time: 210, delta: 3)
        precondition(extinguishedEmber == darkStable, "Cooled debris must leave no lingering ground light")
        terrain.strike(at: SIMD2(-0.5, -4), radius: 1.3, direction: SIMD2(1, 0.3), seed: 27, heat: 1)
        terrain.advance(delta: 0.3)
        let moltenFloor = try pixels(output, time: 211)
        let moltenPause = try pixels(output, time: 220)
        precondition(moltenFloor == moltenPause, "Lava flow and crust must use cooling age, not wall time")
        precondition(
            imageEnergy(moltenFloor) > imageEnergy(darkStable) + 100000,
            "The melt pool must illuminate its floor without a surviving source body")
        terrain.advance(delta: 3)
        let coolingFloor = try pixels(output, time: 223)
        precondition(
            imageEnergy(coolingFloor) < imageEnergy(moltenFloor) && coolingFloor != moltenFloor,
            "Growing stationary crust must progressively cover the hot liquid")
        terrain.advance(delta: 5)
        let frozenFloor = try pixels(output, time: 228)
        precondition(imageEnergy(frozenFloor) < imageEnergy(moltenFloor) / 20)
        terrain.advance(delta: 50)
        let oldFrozenFloor = try pixels(output, time: 278)
        precondition(oldFrozenFloor == frozenFloor, "Frozen residue must stop flowing and glowing")
        precondition(MemoryLayout<MeltPool>.stride == 48 && MemoryLayout<FrameUniformsGPU>.stride == 80)
        // Separate lakes prove that shader emission and ground illumination retain RGB ownership.
        for channel in 0..<3 {
            let colored = SandTerrain()
            var source = SIMD3<Float>(repeating: 0.03)
            source[channel] = 1
            colored.strike(
                at: SIMD2(-0.5, -4), radius: 1.3, direction: SIMD2(1, 0.3),
                seed: 27, heat: 1, color: source)
            colored.advance(delta: 0.3)
            let hot = try pixels(output, time: 0, field: colored)
            var energy = SIMD3<Double>(repeating: 0)
            for i in stride(from: 0, to: hot.count, by: 4) {
                energy += SIMD3(Double(hot[i + 2]), Double(hot[i + 1]), Double(hot[i]))
            }
            precondition(
                energy[channel] > energy[(channel + 1) % 3] * 1.5
                    && energy[channel] > energy[(channel + 2) % 3] * 1.5,
                "Lava and its surroundings must glow in the impacting body's color")
            let pausedColor = try pixels(output, time: 40, field: colored)
            precondition(
                hot == pausedColor,
                "Colored lava must freeze on pause")
            colored.advance(delta: 3)
            let cooling = try pixels(output, time: 43, field: colored)
            precondition(imageEnergy(cooling) < imageEnergy(hot), "Colored lava must cool under its crust")
            colored.advance(delta: 5)
            let cold = try pixels(output, time: 48, field: colored)
            precondition(
                imageEnergy(cold) < imageEnergy(hot) / 20,
                "Inherited color must extinguish when the lake freezes")
        }
        // Floating-point output exposes NaNs that an 8-bit target silently turns into black rectangles.
        let hdrRenderer = try MetalRenderer(shaderURL: url, output: .rgba16Float)
        let hdrDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 480, height: 270, mipmapped: false)
        hdrDescriptor.storageMode = .shared
        hdrDescriptor.usage = [.renderTarget, .shaderRead]
        let hdr = device.makeTexture(descriptor: hdrDescriptor)!
        for age: Float in [-0.1, 0.05, 0.3, 0.7, 1.5, 2.8] {
            showerFlash.shape.z = age
            showerFlash.motion.y = age
            let frame = SimulationFrame(bodies: [showerFlash], newParticles: [], terrain: terrain)
            let command = try hdrRenderer.render(
                frame: frame, time: 0, delta: 0, brightness: 1,
                fade: 1, fill: true, output: hdr, reset: true)
            command.waitUntilCompleted()
            precondition(command.status == .completed)
            var halfPixels = [UInt16](repeating: 0, count: hdr.width * hdr.height * 4)
            hdr.getBytes(
                &halfPixels, bytesPerRow: hdr.width * 8,
                from: MTLRegionMake2D(0, 0, hdr.width, hdr.height), mipmapLevel: 0)
            precondition(
                halfPixels.allSatisfy { $0 & 0x7c00 != 0x7c00 },
                "Every HDR channel must stay finite throughout flight, flash and cooling")
        }
        print(
            "PASS: GPU rigid spin, bounce/settle, opaque depth/cold silhouette, pause/cooling, bounded residence, terrain, HDR and black fade"
        )
    }
}
