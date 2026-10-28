import Foundation
import simd

/// Aligned SIMD structures shared verbatim with Metal; no reference-owned state crosses the GPU boundary.
struct ParticleGPU {
    var position: SIMD4<Float>  // world xy position, xy velocity
    var life: SIMD4<Float>  // size, age (negative for scheduled ejecta), duration, seed
    var color: SIMD4<Float>  // linear RGB, ParticleKind.rawValue
    var owner: SIMD4<Float>  // event identity, ParticleDynamics.rawValue, world z, z velocity
    var orientation: SIMD4<Float> = SIMD4(0, 0, 0, 1)  // unit quaternion, xyzw
    var angular: SIMD4<Float> = SIMD4(0, 0, 0, 1)  // angular velocity in radians/sec; heat retained at landing
}

/// Nine aligned SIMD4 values (144 bytes), in the same order as Metal's BodyGPU declaration.
struct BodyGPU {
    var position: SIMD4<Float>  // xy, radius, opacity
    var color: SIMD4<Float>  // linear RGB, event identity for material ownership/contact
    var motion: SIMD4<Float>  // burst world z, age after ground/air contact, approach glow, seed
    var cloud: SIMD4<Float>  // cloud center xy, radius, pressure
    var shape: SIMD4<Float>  // trajectory slope, crust fraction, impact age, disintegration duration
    var spatial: SIMD4<Float> = .zero  // world xyz center, physical radius
    var contact: SIMD4<Float> = .zero  // fixed world xyz impact point, 1 for ground and 0 for air contact
    var impactEffects: SIMD4<Float> = .zero  // bolide flash, shower radiance, ground tremor strength, reserved
    var flight: SIMD4<Float> = .zero  // unit rear xyz (zero for static diagnostics), speed in image heights/scene second
}

struct SimulationFrame {
    var bodies: [BodyGPU]
    var newParticles: [ParticleGPU]
    var terrain: SandTerrain? = nil
}

/// Five aligned SIMD4 values (80 bytes), uploaded once per frame and shared by every GPU pass.
struct FrameUniformsGPU {
    var viewport: SIMD4<Float>  // pixel width/height, aspect, scene time
    var controls: SIMD4<Float>  // scene delta, brightness, camera shake xy in image-height units
    var counts: SIMD4<UInt32>  // particle capacity, new particle count, ring head, body count
    var options: SIMD4<Float>  // fade, fill mode, reset flag, reserved
    var thermal: SIMD4<UInt32> = .zero  // melt pool count, shock shell count, incoming atmosphere count, reserved
}
