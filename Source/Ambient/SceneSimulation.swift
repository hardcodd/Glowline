import Foundation
import simd

/// Bounded independent arrivals and world-space deposition. The GPU owns material after emission.
final class SceneSimulation {
    private(set) var time: Double = 0
    private(set) var bodies: [SceneBody] = []
    let seed: Double
    let terrain: SandTerrain
    private var nextBirth: Double = 0
    private var nextBolideBirth: Double
    private var meteorShower: MeteorShower
    private var director: SceneDirector
    private var nextID = 0
    private let emitter: ParticleEmitter
    private var cloudCenters: [Int: SIMD4<Float>] = [:]

    init(
        seed: Double = Double.random(in: 0..<100), bodies: [SceneBody] = [], time: Double = 0,
        terrain: SandTerrain = SandTerrain()
    ) {
        self.seed = seed
        self.bodies = bodies
        self.time = time
        self.terrain = terrain
        emitter = ParticleEmitter(seed: seed)
        meteorShower = MeteorShower(seed: seed, time: time)
        director = SceneDirector(seed: seed, time: time)
        nextBolideBirth = time + 2 + hash(seed + 97.3) * 2
        nextBirth = time
        nextID = (bodies.map(\.id).max() ?? -1) + 1
    }

    func advance(delta: Double, aspect: Float, palette: Int, births: Bool) -> SimulationFrame {
        let before = time
        time += delta
        terrain.advance(delta: delta)
        bodies.removeAll { time >= $0.birth + $0.duration }
        let alive = Set(bodies.map(\.id))
        cloudCenters = cloudCenters.filter { alive.contains($0.key) }
        let direction = director.sample(at: time)
        while births && nextBirth <= time && bodies.count < 20 {
            let allowLarge = !bodies.contains { $0.radius >= 0.16 }
            let body = SceneBody(
                id: nextID, birth: max(nextBirth, before), seed: seed,
                composition: direction.arrival(id: nextID, seed: seed),
                arrival: .sporadic(allowMassive: allowLarge))
            bodies.append(body)
            nextID += 1
            nextBirth = body.birth + direction.ordinaryDelay(id: body.id, seed: seed)
        }
        // Dramatic events remain independent, but their cooldown follows the current arrival pressure.
        if births && time >= nextBolideBirth && bodies.count < 20 && !bodies.contains(where: \.model.isBolide)
        {
            let body = SceneBody(
                id: nextID, birth: time, seed: seed, composition: direction.arrival(id: nextID, seed: seed),
                arrival: .bolide)
            bodies.append(body)
            nextID += 1
            nextBolideBirth = time + direction.bolideDelay(id: body.id, seed: seed)
            director.noteClimax(at: time, id: body.id)
        }
        if !births {
            nextBirth = max(nextBirth, time + 1.1)
            nextBolideBirth = max(nextBolideBirth, time + 2)
        }
        let showerWasActive = meteorShower.isActive(at: before)
        for (birth, member) in meteorShower.arrivals(
            at: time, enabled: births, capacity: 20 - bodies.count,
            activity: direction.activity, tone: direction.hue, heading: direction.heading)
        {
            bodies.append(
                SceneBody(id: nextID, birth: max(before, birth), seed: seed, arrival: .shower(member)))
            nextID += 1
        }
        if showerWasActive && !meteorShower.isActive(at: time) {
            director.noteClimax(at: time, id: nextID)
        }

        resolveBodyCollisions(bodies: &bodies, from: before, to: time, aspect: aspect)
        resolveGroundContacts(from: before, aspect: aspect, palette: palette)

        var gpuBodies: [BodyGPU] = []
        var particles: [ParticleGPU] = []
        for index in bodies.indices {
            var body = bodies[index]
            let age = time - body.birth
            let center = body.worldPosition(age: age, aspect: aspect)
            let impact = body.worldPosition(age: body.impactAge, aspect: aspect)
            let contact = body.collision?.point ?? body.groundContact?.point ?? SIMD3(impact.x, 0, impact.z)
            let resolvedAge = body.collision?.age ?? body.groundContact?.age
            let hitAge = resolvedAge.map { Float(age - $0) } ?? -1
            let color = bodyColor(body.hue, palette: palette) * (body.model.showerMember == nil ? 1 : 1.65)
            let screen = SceneCamera.project(center)
            let projectedRadius = body.apparentRadius(at: center)
            let gap = screen.y - (0.5 + projectedRadius)
            let glow = clamp(1 - gap / (body.screenSpeed * body.approachGlowDuration), 0, 1)
            let cloudAge = clamp(hitAge / body.cloudLifetime, 0, 1)
            let burstOrigin = contact
            var cloud =
                cloudCenters[body.id]
                ?? SIMD4(burstOrigin.x, burstOrigin.y, (body.variation - 0.5) * 0.03, 0.06)
            if hitAge >= 0 {
                cloud.x += cloud.z * Float(delta)
                cloud.y += cloud.w * Float(delta)
                cloudCenters[body.id] = cloud
            }
            let opacity: Float =
                body.groundContact != nil
                ? (hitAge < body.disintegrationDuration ? 1 : 0)
                : clamp(1 - hitAge / body.disintegrationDuration, 0, 1)
            gpuBodies.append(
                BodyGPU(
                    position: SIMD4(screen.x, screen.y, projectedRadius, opacity),
                    color: SIMD4(color, Float(body.id)),
                    motion: SIMD4(burstOrigin.z, hitAge, glow * glow, body.variation * 83),
                    cloud: SIMD4(
                        cloud.x, cloud.y, min(body.worldRadius * 0.85, 3.0) + cloudAge * 0.8,
                        hitAge > 0 && cloudAge < 1 ? sin(cloudAge * .pi) : 0),
                    shape: SIMD4(body.slope, body.crustFraction, hitAge, body.disintegrationDuration),
                    spatial: SIMD4(center, body.worldRadius),
                    contact: SIMD4(contact, body.collision == nil ? 1 : 0),
                    impactEffects: SIMD4(
                        body.model.isBolide ? 1 : 0, body.model.showerMember == nil ? 0 : 1,
                        body.impactShakeStrength, 0),
                    flight: SIMD4(-simd_normalize(body.entryVelocity), body.screenSpeed)))

            emitter.emitTrail(
                body: &body, from: before, to: time, resolvedAge: resolvedAge,
                aspect: aspect, palette: palette, color: color, terrain: terrain, into: &particles)
            if hitAge >= 0 && !body.impactEmitted {
                body.impactEmitted = true
                emitter.emitImpact(
                    body: body, at: burstOrigin, color: color, palette: palette,
                    terrain: terrain, into: &particles, launchOffset: max(0, Float(delta) - hitAge))
            }

            bodies[index] = body
        }
        for launch in terrain.takeShockSoil() {
            for kind: ParticleKind in [.regolithGrain, .soilDust] {
                particles.append(
                    ParticleGPU(
                        position: SIMD4(launch.point.x, launch.point.y, launch.velocity.x, launch.velocity.y),
                        life: SIMD4(
                            kind == .regolithGrain ? 0.012 : 0.08, 0, kind == .regolithGrain ? 2.2 : 0.85,
                            launch.seed),
                        color: SIMD4(0.57, 0.59, 0.63, kind.rawValue),
                        owner: SIMD4(
                            -1, ParticleDynamics.ballistic.rawValue, launch.point.z, launch.velocity.z)))
            }
        }
        return SimulationFrame(
            bodies: gpuBodies, newParticles: Array(particles.prefix(4096)), terrain: terrain)
    }

    /// Swept root search against the *current* height field, including earlier overlapping craters.
    /// Only the first contact stamps the terrain; later object removal has no effect on it.
    private func resolveGroundContacts(from before: Double, aspect: Float, palette: Int) {
        for index in bodies.indices where bodies[index].collision == nil && bodies[index].groundContact == nil
        {
            let body = bodies[index]
            let age = time - body.birth
            let end = body.worldPosition(age: age, aspect: aspect)
            guard end.y - body.worldRadius <= terrain.height(at: SIMD2(end.x, end.z)) else { continue }
            var low = max(0, before - body.birth)
            let start = body.worldPosition(age: low, aspect: aspect)
            if start.y - body.worldRadius <= terrain.height(at: SIMD2(start.x, start.z)) {
                low = max(0, body.entryAge)
            }
            var high = age
            for _ in 0..<28 {
                let middle = (low + high) * 0.5
                let p = body.worldPosition(age: middle, aspect: aspect)
                if p.y - body.worldRadius > terrain.height(at: SIMD2(p.x, p.z)) {
                    low = middle
                } else {
                    high = middle
                }
            }
            let center = body.worldPosition(age: high, aspect: aspect)
            let point = SIMD3(center.x, terrain.height(at: SIMD2(center.x, center.z)), center.z)
            bodies[index].groundContact = BodyContact(age: high, center: center, point: point)
            terrain.strike(
                at: SIMD2(point.x, point.z), radius: body.craterRadius,
                direction: SIMD2(body.entryVelocity.x, body.entryVelocity.z), seed: Float(body.id),
                elapsed: age - high, heat: body.impactHeat,
                penetration: clamp(body.groundPenetration / body.worldRadius, 0, 1),
                obliquity: simd_length(SIMD2(body.entryVelocity.x, body.entryVelocity.z))
                    / simd_length(body.entryVelocity),
                color: bodyColor(body.hue, palette: palette))
            if body.model.isBolide {
                terrain.launchShock(
                    at: SIMD2(point.x, point.z), bodyRadius: body.worldRadius,
                    direction: SIMD2(body.entryVelocity.x, body.entryVelocity.z), seed: Float(body.id),
                    elapsed: age - high)
            }
        }
    }

}
