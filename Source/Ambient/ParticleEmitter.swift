import Foundation
import simd

/// Owns deterministic particle randomness; SceneSimulation retains body and terrain ownership.
/// Calls must remain in source order so structural changes preserve the accepted scene.
final class ParticleEmitter {
    private let seed: Double
    private var serial = 0

    init(seed: Double) { self.seed = seed }

    /// Integrates detached wake material along the flight segment and retains fractional emission.
    func emitTrail(
        body: inout SceneBody, from before: Double, to time: Double, resolvedAge: Double?,
        aspect: Float, palette: Int, color: SIMD3<Float>, terrain: SandTerrain,
        into particles: inout [ParticleGPU]
    ) {
        let age = time - body.birth
        // Integrate the source along the path, never translate an existing trail with its parent.
        let start = max(0, before - body.birth)
        let end = min(age, resolvedAge ?? age)
        if end > start {
            let rate =
                Double(450 + min(body.radius, 0.85) * 2000) * (body.model.showerMember == nil ? 1 : 0.60)
            body.pendingTrailParticles += (end - start) * rate
            let count = min(1024, Int(body.pendingTrailParticles))
            body.pendingTrailParticles -= Double(count)
            let rear = -simd_normalize(body.entryVelocity)
            let across = simd_normalize(simd_cross(rear, -SceneCamera.forward))
            let normal = simd_cross(across, rear)
            let style = body.trailStyle
            let phase = Float(body.id) * 2.39996
            let accent = bodyColor(body.hue + 0.12, palette: palette)
            for n in 0..<count {
                let t = start + (end - start) * (Double(n) + 0.5) / Double(count)
                let source = body.worldPosition(age: t, aspect: aspect)
                if SceneCamera.project(source).y - body.apparentRadius(at: source) > 0.7 { continue }
                let groundHeight = terrain.height(at: SIMD2(source.x, source.z))
                let exposure = clamp(
                    (source.y + body.worldRadius - groundHeight) / (2 * body.worldRadius), 0, 1)
                if exposure <= 0 { continue }
                let random = random4()
                let ember = random.z > (style == .meteor ? 0.72 : 0.88)
                let stream = !ember && random.z < (style == .plasma ? 0.50 : style == .comet ? 0.34 : 0.22)
                let kind: ParticleKind =
                    ember ? .ember : stream ? (style == .plasma ? .plasmaTrail : .ionTrail) : .vapor
                // Moving vents feed one wake; luminous filaments remain inside the dust envelope.
                let vent = floor(random.x * 4) / 3 * 2 - 1
                let pulse = sin(Float(t) * 1.7 + phase + vent * 2.1)
                let cross =
                    stream
                    ? vent * (style == .comet ? 0.18 : 0.62) + pulse * 0.22
                    : (random.x * 2 - 1) * 0.90
                let rearY = sqrt(max(0, 1 - cross * cross))
                let sideOffset: SIMD3<Float> = across * cross
                let rearOffset: SIMD3<Float> = rear * rearY
                let depthOffset: SIMD3<Float> = normal * (random.w - 0.5) * 0.35
                let surfaceOffset: SIMD3<Float> = (sideOffset + rearOffset + depthOffset) * body.worldRadius
                let point: SIMD3<Float> = source + surfaceOffset
                if point.y <= terrain.height(at: SIMD2(point.x, point.z)) { continue }
                let fan: Float =
                    style == .comet
                    ? cross * (stream ? 0.07 : 0.12)
                    : cross * (ember ? 0.20 : 0.065)
                let flow: Float = style == .plasma ? 0.19 : style == .comet ? 0.12 : 0.065
                let velocity: SIMD3<Float> =
                    (rear * flow * (0.75 + random.y * 0.65)
                        + across * (fan + pulse * 0.025)
                        + normal
                        * ((random.w - 0.5) * (ember ? 0.12 : 0.035)
                            + (style == .plasma ? sin(Float(t) * 2.1 + vent * 1.3 + phase) * 0.055 : 0)))
                    * body.physicalScale
                let baseSize = min(0.034, body.radius * (stream ? 0.24 : 0.25))
                let size = ember ? 0.0015 + random.w * 0.0025 : baseSize * (0.65 + random.w * 0.75)
                let lifetime = stream ? (style == .plasma ? 3.8 : 3.0) : body.trailLifetime
                let tint = stream ? color * 0.65 + accent * 0.35 : color
                particles.append(
                    ParticleGPU(
                        position: SIMD4(point.x, point.y, velocity.x, velocity.y),
                        life: SIMD4(
                            size * body.physicalScale * (body.model.showerMember == nil ? 1 : 1.35),
                            0, lifetime * (0.7 + random.y * 0.3), random.y * 100),
                        color: SIMD4(tint * exposure, kind.rawValue),
                        owner: SIMD4(
                            Float(body.id), (ember ? ParticleDynamics.wakeSpark : .wake).rawValue, point.z,
                            velocity.z)))
            }
        }
    }

    /// Incandescent debris and dust originate at contact. The GPU owns rigid spin, landing and cooling.
    func emitImpact(
        body: SceneBody, at impact: SIMD3<Float>, color: SIMD3<Float>, palette: Int, terrain: SandTerrain,
        into particles: inout [ParticleGPU]
    ) {
        let scale = body.radius
        let collision = body.collision != nil
        let gasCount = Int((180 + scale * 420) * (body.model.isBolide ? 1.5 : 1))
        let emberCount = Int((320 + scale * 520) * (body.model.isBolide ? 2 : 1))
        let shardCount = Int((36 + scale * 110) * (body.model.isBolide ? 2 : 1))
        let spread = scale * 0.88
        let verticalSpread = spread * 0.86
        let power = (0.55 + sqrt(scale) * 0.9) * (body.model.isBolide ? 1.9 : 1)

        // Superheated asteroids melt into their crater; ordinary impacts and air collisions keep fragments.
        let kinds: [ParticleKind] =
            collision
            ? [.impactGas, .ember, .rockFragment]
            : body.makesLavaLake
                ? [.soilDust, .regolithGrain, .ember]
                : [.soilDust, .regolithGrain, .ember, .rockFragment]
        for kind in kinds {
            let gas = kind.isGas
            let grain = kind == .regolithGrain
            let baseCount =
                grain ? Int(140 + scale * 450) : gas ? gasCount : kind == .ember ? emberCount : shardCount
            let count = body.model.showerMember == nil ? baseCount : Int(Float(baseCount) * 0.70)
            for _ in 0..<count {
                let r = random4()
                // Narrow radial fans carry coarse soil outward; oblique momentum biases their range.
                let soil = grain || kind == .soilDust
                let axisAngle = atan2(body.entryVelocity.z, body.entryVelocity.x)
                let angle =
                    soil
                    ? floor(r.x * 17) / 17 * .pi * 2 + axisAngle + (r.z - 0.5) * 0.075
                    : r.x * .pi * 2
                let depth = r.w * 2 - 1
                let disk = sqrt(r.z)
                var origin =
                    impact + SIMD3(
                        cos(angle) * disk * spread,
                        (collision ? sin(angle) : abs(sin(angle))) * disk * verticalSpread,
                        depth * spread * 0.5) * body.physicalScale
                if kind == .soilDust || grain {
                    origin.y = terrain.height(at: SIMD2(origin.x, origin.z)) + 0.015
                }
                let lobe = floor(r.x * 9) / 9 * .pi * 2
                let launch = gas ? lobe + (r.y - 0.5) * 0.35 : angle
                let direction = SIMD2(cos(launch), collision ? sin(launch) : abs(sin(launch)) * 0.85 + 0.12)
                let speed =
                    (kind == .soilDust
                        ? 0.22 + r.y * 0.48
                        : gas
                            ? 0.10 + r.y * 0.23
                            : kind == .rockFragment ? 0.20 + r.y * 0.44 : 0.16 + r.y * 0.60) * power
                let size: Float =
                    grain
                    ? 0.001 + pow(r.w, 2) * 0.0055
                    : gas
                        ? (kind == .soilDust ? 0.014 + r.w * 0.03 : 0.014 + r.w * 0.023) * (0.7 + scale * 1.6)
                        : kind == .rockFragment
                            ? (0.003 + pow(r.z, 3) * 0.009) * (0.65 + scale)
                            : 0.0007 + r.w * 0.002
                let life =
                    grain
                    ? 1.8 + r.z * 1.4
                    : gas ? (kind == .soilDust ? 0.7 + r.z : 1.8 + r.z * 1.1) : 4.5 + r.z * 1.5
                // Colored ejecta surround a warm flash; dust itself remains neutral regolith.
                let ejecta =
                    body.model.showerMember != nil
                    ? bodyColor(body.hue + (r.w - 0.5) * 0.24, palette: palette) * 1.8
                    : body.model.isBolide
                        ? bodyColor(body.hue + r.w * 0.45, palette: palette) * 0.7
                            + SIMD3<Float>(0.3, 0.18, 0.07) : color
                let tint = kind == .soilDust || grain ? SIMD3<Float>(0.57, 0.59, 0.63) : ejecta
                let hueShift = SIMD3<Float>(1, 0.72 + r.w * 0.28, 0.65 + r.y * 0.35)
                let contactState = ParticleDynamics.ballistic.rawValue
                var velocity =
                    kind == .soilDust
                    ? SIMD3(cos(angle) * (0.5 + r.y), 0.35 + r.z * 0.8, sin(angle) * (0.5 + r.y)) * speed
                        * body.physicalScale
                    : SIMD3(direction.x, direction.y, depth * 0.45) * speed * body.physicalScale
                if grain {
                    velocity =
                        SIMD3(cos(angle), 0.35 + r.z * 0.95, sin(angle))
                        * (0.35 + r.y * 0.9) * power * body.physicalScale
                        + SIMD3(body.entryVelocity.x, 0, body.entryVelocity.z) * 0.18
                } else if !collision && !gas {
                    let elevation = 0.25 + r.z * 0.9
                    velocity =
                        SIMD3(cos(angle), elevation, sin(angle)) * speed * body.physicalScale
                        + SIMD3(body.entryVelocity.x, 0, body.entryVelocity.z)
                        * (kind == .rockFragment ? 0.14 : 0.06)
                }
                let axis = simd_normalize(
                    SIMD3(r.x * 2 - 1, r.z * 2 - 1, r.w * 2 - 1) + SIMD3(repeating: 0.001))
                let rotation = simd_quatf(angle: r.y * .pi * 2, axis: axis)
                particles.append(
                    ParticleGPU(
                        position: SIMD4(origin.x, origin.y, velocity.x, velocity.y),
                        life: SIMD4(size * body.physicalScale, 0, life, r.y * 100),
                        color: SIMD4(tint * hueShift, kind.rawValue),
                        owner: SIMD4(Float(body.id), contactState, origin.z, velocity.z),
                        orientation: kind == .rockFragment ? rotation.vector : SIMD4(0, 0, 0, 1),
                        angular: kind == .rockFragment ? SIMD4(axis * (3 + r.w * 8), 1) : .zero))
            }
        }
    }

    private func random4() -> SIMD4<Float> {
        serial += 1
        let n = Double(serial) + seed * 1000
        return SIMD4(Float(hash(n)), Float(hash(n + 713.3)), Float(hash(n + 91.7)), Float(hash(n + 1321.1)))
    }
}
