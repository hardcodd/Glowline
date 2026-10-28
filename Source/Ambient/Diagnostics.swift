import AppKit
import MetalKit

/// Reproducible offscreen stress includes ordinary geometry, a large asteroid, its impact, and deposited material.
func benchmark(shader: URL, directory: URL) throws {
    let renderer = try MetalRenderer(shaderURL: shader)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 3440, height: 1440, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let output = renderer.device.makeTexture(descriptor: descriptor) else {
        throw RenderFailure.unavailable("Benchmark target allocation failed")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let large = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    let simulation = SceneSimulation(seed: 1, bodies: [large], time: large.groundAge - 0.5)
    var captures: [String] = []
    let start = CACurrentMediaTime()
    for frame in 0..<480 {
        let sample = simulation.advance(delta: 1 / 30, aspect: 3440 / 1440, palette: 0, births: true)
        let command = try renderer.render(
            frame: sample, time: Float(simulation.time), delta: 1 / 30, brightness: 1, fade: 1, fill: true,
            output: output)
        command.waitUntilCompleted()
        if command.status == .error {
            throw command.error ?? RenderFailure.unavailable("GPU benchmark failed")
        }
        if [70, 120, 128, 145, 170, 210, 280].contains(frame) {
            let name = "metal-stress-\(frame).png"
            try writePNG(texture: output, to: directory.appendingPathComponent(name))
            captures.append(name)
        }
    }
    // A fast meteor strikes a visible superheated limb: inspect contact-space debris and the intact survivor.
    let aspect: Float = 3440 / 1440
    let bigAge = Double((0.5 + large.apparentRadius + large.entryLeadDistance) / large.screenSpeed)
    let meteor = SceneBody(id: 91, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    let smallAge = Double((0.5 + meteor.apparentRadius + meteor.entryLeadDistance - 0.25) / meteor.screenSpeed)
    let contact = SceneSimulation(
        seed: 1,
        bodies: [
            SceneBody(id: large.id, birth: 100 - bigAge, seed: 1, depthScale: 1, depthDirection: 0),
            SceneBody(id: meteor.id, birth: 100 - smallAge, seed: 1, depthScale: 1, depthDirection: 0),
        ], time: 100)
    for frame in 0..<180 {
        let sample = contact.advance(delta: 1 / 60, aspect: aspect, palette: 0, births: false)
        let command = try renderer.render(
            frame: sample, time: Float(contact.time), delta: 1 / 60,
            brightness: 1, fade: 1, fill: true, output: output, reset: frame == 0)
        command.waitUntilCompleted()
        if command.status == .error {
            throw command.error ?? RenderFailure.unavailable("Collision benchmark failed")
        }
        if [0, 30, 60, 100].contains(frame) {
            let name = "metal-contact-\(frame).png"
            try writePNG(texture: output, to: directory.appendingPathComponent(name))
            captures.append(name)
        }
    }
    let stats = renderer.metrics.snapshot()
    // A fixed size catalog makes body shape and trajectory alignment inspectable without waiting for arrivals.
    let candidates = (0..<10000).map {
        SceneBody(id: $0, birth: 0, seed: 13.7, depthScale: 1, depthDirection: 0)
    }
    let radii: [Float] = [0.04, 0.065, 0.10, 0.17, 0.24]
    let catalog = radii.enumerated().map { index, radius -> BodyGPU in
        let body = candidates.min { abs($0.radius - radius) < abs($1.radius - radius) }!
        let color = bodyColor(Float(index) * 0.17 + 0.03, palette: 0)
        let center = SceneCamera.world(SIMD2(-0.98 + Float(index) * 0.47, 0), distance: body.referenceDepth)
        return BodyGPU(
            position: SIMD4(-0.98 + Float(index) * 0.47, 0, radius, 1),
            color: SIMD4(color, Float(body.id)), motion: SIMD4(0, -1, 1, body.variation * 83), cloud: .zero,
            shape: SIMD4(
                radius >= 0.16 ? 0 : (index % 2 == 0 ? -0.18 : 0.18), body.crustFraction, -1,
                body.disintegrationDuration),
            spatial: SIMD4(center, body.referenceDepth * radius / sqrt(1 + radius * radius)),
            contact: SIMD4(center.x, 0, center.z, 1))
    }
    let catalogCommand = try renderer.render(
        frame: SimulationFrame(bodies: catalog, newParticles: []), time: 20, delta: 0,
        brightness: 1, fade: 1, fill: true, output: output, reset: true)
    catalogCommand.waitUntilCompleted()
    if catalogCommand.status == .error {
        throw catalogCommand.error ?? RenderFailure.unavailable("Appearance catalog failed")
    }
    try writePNG(texture: output, to: directory.appendingPathComponent("metal-appearance.png"))
    captures.append("metal-appearance.png")
    let report: [String: Any] = [
        "gpu": renderer.device.name, "width": 3440, "height": 1440, "samples": stats.samples,
        "gpuMedianMs": stats.median, "gpuP95ms": stats.p95, "gpuMaxMs": stats.max, "gpuErrors": stats.errors,
        "wallSeconds": CACurrentMediaTime() - start, "captures": captures,
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("metal-benchmark.json"))
    print(String(decoding: data, as: UTF8.self))
}

func writePNG(texture: MTLTexture, to url: URL) throws {
    let bytesPerRow = texture.width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
    texture.getBytes(
        &bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0)
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
        let image = CGImage(
            width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                .byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    else {
        throw RenderFailure.unavailable("Capture conversion failed")
    }
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}
