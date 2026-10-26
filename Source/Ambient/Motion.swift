import Foundation
import simd

func hash(_ value: Double) -> Double {
    let n = sin(value * 127.1 + 311.7) * 43758.5453
    return n - floor(n)
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T { min(high, max(low, value)) }

/// A flight contact freezes the broken body while its deposited trail disperses independently.
struct StarCollision {
    let age: Double
    let center: SIMD2<Float>
    let point: SIMD2<Float>
}

/// Deterministic event contract, independent of display cadence and rendering backend.
struct Star {
    let id: Int
    let birth: Double
    let radius: Float
    let giant: Bool
    let speed: Float
    let bend: Float
    let lane: Float
    let hue: Float
    var collision: StarCollision?
    var exploded = false
    var emitted: Double = 0

    init(id: Int, birth: Double, seed: Double, allowLarge: Bool = true) {
        self.id = id; self.birth = birth
        let size = hash(Double(id) * 8.17 + seed)
        let block = Double(id / 80)
        let offset = 10 + Int(hash(block * 17.31 + seed + 41) * 30)
        giant = allowLarge && hash(block * 9.73 + seed + 83) < 0.25 && id % 80 == offset
        let candidate = giant ? 0.72 + size * 0.24 : 0.035 + 0.23 * pow(size, 7)
        radius = Float(!allowLarge && candidate >= 0.16 ? 0.07 + size * 0.06 : candidate)
        speed = 0.052 + 0.0012 / (radius * radius)
        bend = Float(hash(Double(id) * 3.1 + seed))
        lane = Float(hash(Double(id) * 5.7 + seed))
        hue = Float(Double(id) * 0.381966 + seed * 0.071)
    }

    /// Small bodies use an irregular ablation shell; larger objects transition smoothly to solar geometry.
    var meteorFraction: Float {
        let t = clamp((radius - 0.065) / 0.085, 0, 1)
        return 1 - t * t * (3 - 2 * t)
    }

    var sizeFraction: Float { clamp((radius - 0.035) / 0.925, 0, 1) }
    var cue: Float { 0.25 + 2.75 * sizeFraction }
    var approach: Float { max(radius * 4, speed * max(1.8, cue)) }
    var entryAge: Double { Double(approach / speed) }
    /// A giant keeps descending until only its upper cap remains in the bottom third.
    var impactDepth: Float { giant ? radius * 0.65 : 0 }
    var impactAge: Double { collision?.age ?? Double((1 + radius + approach + impactDepth) / speed) }
    var breakupLife: Float { 0.22 + 0.8 * sizeFraction }
    var cloudLife: Float { 4.8 + 1.7 * sizeFraction }
    var wakeLife: Float { 2.5 + 4.5 * sizeFraction }
    var duration: Double { impactAge + Double(max(cloudLife, wakeLife)) }
    var side: Float { giant ? 0 : id % 4 == 0 ? -1 : id % 4 == 1 ? 1 : 0 }
    var slope: Float {
        if radius >= 0.16 { return 0 }
        if side != 0 { return -side * (0.25 + bend * 0.75) * min(tan(0.15), radius * 0.8 / (1 + 2 * radius)) }
        let direction = bend * 2 - 1
        // Most arrivals remain calm; occasional opposite diagonals create crossings and contacts.
        let angle: Float = abs(direction) > 0.72 ? .pi * 34 / 180 : .pi / 15
        return direction * tan(angle)
    }

    func position(age: Double, aspect: Float) -> SIMD2<Float> {
        if let collision, age >= collision.age { return collision.center }
        let halfDrift = slope * (1 + 2 * radius) * 0.5
        let limit = max(0, aspect / 2 - radius * 0.7 - abs(halfDrift))
        let center = clamp((lane - 0.5) * max(0.1, aspect - radius * 3.4), -limit, limit)
        let entry = side != 0 ? side * (aspect / 2 - radius * 0.1) : center - halfDrift
        let distance = Float(max(0, age)) * speed
        return SIMD2(entry + slope * (distance - approach), 0.5 + radius + approach - distance)
    }
}

/// First contact along a relative segment; detects fast bodies that cross between frames.
func sweptContact(from start: SIMD2<Float>, to end: SIMD2<Float>, radius: Float) -> Float? {
    let c = simd_length_squared(start) - radius * radius
    if c <= 0 { return 0 }
    let travel = end - start
    let a = simd_length_squared(travel)
    guard a > 0.00000001 else { return nil }
    let b = simd_dot(start, travel)
    let discriminant = b * b - a * c
    guard b < 0 && discriminant >= 0 else { return nil }
    let t = (-b - sqrt(discriminant)) / a
    return (0...1).contains(t) ? t : nil
}

/// Resolve in time order. Only the smaller body breaks; the survivor's motion and lifetime never change.
/// At most 20 bodies produce 190 candidate pairs, without a particle-level CPU simulation.
func resolveStarCollisions(stars: inout [Star], from before: Double, to time: Double, aspect: Float) {
    var contacts: [(time: Double, a: Int, b: Int, point: SIMD2<Float>)] = []
    for a in stars.indices where stars[a].collision == nil && !stars[a].exploded {
        for b in stars.indices where b > a && stars[b].collision == nil && !stars[b].exploded {
            let first = stars[a], second = stars[b]
            let start = max(before, first.birth, second.birth)
            let end = min(time, first.birth + first.impactAge, second.birth + second.impactAge)
            guard end > start else { continue }
            let a0 = first.position(age: start - first.birth, aspect: aspect)
            let b0 = second.position(age: start - second.birth, aspect: aspect)
            let a1 = first.position(age: end - first.birth, aspect: aspect)
            let b1 = second.position(age: end - second.birth, aspect: aspect)
            // The luminous corona is not solid: use the compact body under its ablation shell.
            let r1 = first.radius * 0.9, r2 = second.radius * 0.9
            guard let t = sweptContact(from: a0 - b0, to: a1 - b1, radius: r1 + r2) else { continue }
            let ca = a0 + (a1 - a0) * t, cb = b0 + (b1 - b0) * t
            let point = (ca * r2 + cb * r1) / (r1 + r2)
            guard abs(point.x) <= aspect / 2 && (-0.5...0.5).contains(point.y) else { continue }
            contacts.append((start + (end - start) * Double(t), a, b, point))
        }
    }
    for contact in contacts.sorted(by: { $0.time < $1.time }) {
        guard stars[contact.a].collision == nil && stars[contact.b].collision == nil else { continue }
        let a = stars[contact.a], b = stars[contact.b]
        let victim = a.radius == b.radius ? (a.id > b.id ? contact.a : contact.b)
            : (a.radius < b.radius ? contact.a : contact.b)
        let age = contact.time - stars[victim].birth
        let center = stars[victim].position(age: age, aspect: aspect)
        stars[victim].collision = StarCollision(age: age, center: center, point: contact.point)
    }
}

/// Aligned SIMD structures shared verbatim with Metal; no reference-owned state crosses the GPU boundary.
struct Particle {
    var position: SIMD4<Float> // xy position, zw velocity
    var life: SIMD4<Float> // size, age, duration, seed
    var color: SIMD4<Float> // linear RGB, kind (0 vapor, 1 ember, 2 impact gas, 3 hot fragment)
    var owner: SIMD4<Float> // event identity, impact impulse applied, depth, reserved
}

struct SunGPU {
    var position: SIMD4<Float> // xy, radius, opacity
    var color: SIMD4<Float> // linear RGB, event identity for material ownership/contact
    var motion: SIMD4<Float> // impact x, age after impact, approach glow, seed
    var cloud: SIMD4<Float> // cloud center xy, radius, pressure
    var shape: SIMD4<Float> // trajectory slope, ablation fraction, impact age, breakup duration
}

struct SimulationFrame { var suns: [SunGPU]; var spawns: [Particle] }

func starColor(_ hue: Float, palette: Int) -> SIMD3<Float> {
    let h = palette == 1 ? 0.48 + (hue - floor(hue)) * 0.32 : palette == 2 ? 0.92 + (hue - floor(hue)) * 0.22 : hue
    let k = SIMD3<Float>(0, 2/3, 1/3)
    let p = abs(simd_fract(SIMD3(repeating: h) + k) * 6 - SIMD3(repeating: 3))
    let rgb = simd_clamp(p - SIMD3(repeating: 1), SIMD3(repeating: 0), SIMD3(repeating: 1))
    return SIMD3(repeating: 0.025) + rgb * 0.975
}

/// Bounded independent arrivals and world-space deposition. The GPU owns material after emission.
final class Universe {
    private(set) var time: Double = 0
    private(set) var stars: [Star] = []
    let seed: Double
    private var nextBirth: Double = 0
    private var nextID = 0
    private var serial = 0
    private var cloudCenters: [Int: SIMD4<Float>] = [:]

    init(seed: Double = Double.random(in: 0..<100), stars: [Star] = [], time: Double = 0) {
        self.seed = seed
        self.stars = stars
        self.time = time
        nextBirth = time
        nextID = (stars.map(\.id).max() ?? -1) + 1
    }

    /// Review-only preset uses normal event geometry and the same emission/renderer path.
    func stageGiant(includeDescent: Bool = false) {
        let giant = Star(id: 18, birth: 0, seed: 1)
        let descent = includeDescent ? Double(giant.impactDepth / giant.speed) : 0
        stars = [giant]; time = giant.impactAge - 4 - descent; nextBirth = time + 1.1; nextID = 19
    }

    func advance(delta: Double, aspect: Float, palette: Int, births: Bool) -> SimulationFrame {
        let before = time
        time += delta
        stars.removeAll { time >= $0.birth + $0.duration }
        let alive = Set(stars.map(\.id))
        cloudCenters = cloudCenters.filter { alive.contains($0.key) }
        while births && nextBirth <= time && stars.count < 20 {
            let allowLarge = !stars.contains { $0.radius >= 0.16 }
            let star = Star(id: nextID, birth: max(nextBirth, before), seed: seed, allowLarge: allowLarge)
            stars.append(star); nextID += 1
            let pressure = clamp(0.5 + 0.33 * sin(nextBirth * 0.047 + seed) + 0.17 * sin(nextBirth * 0.113 + seed * 2), 0, 1)
            nextBirth = star.birth + 1.1 + hash(Double(star.id) * 6.71 + seed + 3) * (2.3 + pow(1 - pressure, 2) * 11)
        }
        if !births { nextBirth = max(nextBirth, time + 1.1) }

        resolveStarCollisions(stars: &stars, from: before, to: time, aspect: aspect)

        var suns: [SunGPU] = [], particles: [Particle] = []
        for index in stars.indices {
            var star = stars[index]
            let age = time - star.birth
            let center = star.position(age: age, aspect: aspect)
            let impact = star.position(age: star.impactAge, aspect: aspect)
            let hitAge = Float(age - star.impactAge)
            let color = starColor(star.hue, palette: palette)
            let gap = center.y - (0.5 + star.radius)
            let glow = clamp(1 - gap / (star.speed * star.cue), 0, 1)
            let cloudAge = clamp(hitAge / star.cloudLife, 0, 1)
            var cloud = cloudCenters[star.id] ?? SIMD4(star.collision?.point.x ?? impact.x, star.collision?.point.y ?? -0.5, (star.bend - 0.5) * 0.03, 0.06)
            if hitAge >= 0 {
                cloud.x += cloud.z * Float(delta); cloud.y += cloud.w * Float(delta)
                cloudCenters[star.id] = cloud
            }
            suns.append(SunGPU(position: SIMD4(center.x, center.y, star.radius, clamp(1 - hitAge / star.breakupLife, 0, 1)),
                               color: SIMD4(color, Float(star.id)), motion: SIMD4(impact.x, hitAge, glow * glow, star.bend * 83),
                               cloud: SIMD4(cloud.x, cloud.y, min(star.radius * 0.85, 0.78) + cloudAge * 0.32,
                                            hitAge > 0 && cloudAge < 1 ? sin(cloudAge * .pi) : 0),
                               shape: SIMD4(star.slope, star.meteorFraction, hitAge, star.breakupLife)))

            // Integrate the source along the path, never translate an existing trail with its parent.
            let start = max(0, before - star.birth)
            let end = min(age, star.impactAge)
            if end > start {
                let rate = Double(450 + min(star.radius, 0.85) * 2000)
                star.emitted += (end - start) * rate
                let count = min(1024, Int(star.emitted))
                star.emitted -= Double(count)
                let rear = simd_normalize(SIMD2(-star.slope, 1))
                let across = SIMD2(rear.y, -rear.x)
                for n in 0..<count {
                    let t = start + (end - start) * (Double(n) + 0.5) / Double(count)
                    let source = star.position(age: t, aspect: aspect)
                    if source.y - star.radius > 0.7 { continue }
                    let random = random4()
                    // A compact rear hemisphere feeds an asymmetric sheath, without a solid pointed drop.
                    let cross = (random.x * 2 - 1) * 0.92
                    let rearY = sqrt(max(0, 1 - cross * cross))
                    let lateral = cross * star.radius * (1 - 0.16 * star.meteorFraction)
                    let limb = rearY * star.radius * (1 + 0.08 * star.meteorFraction)
                    let point = source + across * lateral + rear * limb
                    let velocity = across * (lateral / star.radius * 0.012 + (random.y - 0.5) * 0.012) + rear * 0.006
                    let ember = random.z > 0.9
                    particles.append(Particle(position: SIMD4(point.x, point.y, velocity.x, velocity.y),
                        life: SIMD4(ember ? 0.0015 + random.w * 0.002 : min(0.026, star.radius * 0.21) * (0.6 + random.w), 0, star.wakeLife * (0.6 + random.z * 0.4), random.y * 100),
                        color: SIMD4(color, ember ? 1 : 0), owner: SIMD4(Float(star.id), 0, 0, 0)))
                }
            }
            if hitAge >= 0 && !star.exploded {
                star.exploded = true
                emitImpact(star: star, at: star.collision?.point ?? SIMD2(impact.x, -0.5), color: color, into: &particles)
            }

            stars[index] = star
        }
        return SimulationFrame(suns: suns, spawns: Array(particles.prefix(4096)))
    }

    /// Finite layered burst. Giant origins cover the visible stellar mass instead of a single small emitter.
    private func emitImpact(star: Star, at impact: SIMD2<Float>, color: SIMD3<Float>, into particles: inout [Particle]) {
        let scale = min(star.radius, 0.95)
        let gasCount = Int(180 + scale * 420)
        let emberCount = Int(320 + scale * 520)
        let shardCount = Int(36 + scale * 110)
        let spread = scale * 0.88
        let collision = star.collision != nil
        let verticalSpread = spread * (star.giant ? 0.34 : 0.86)
        let power = 0.55 + sqrt(scale) * 0.9

        // Gas first, then incandescent debris: large fragments remain readable against the cloud.
        for kind in [2, 1, 3] {
            let count = kind == 2 ? gasCount : kind == 1 ? emberCount : shardCount
            for _ in 0..<count {
                let r = random4()
                let angle = r.x * .pi * 2
                let depth = r.w * 2 - 1
                let disk = sqrt(r.z)
                let origin = SIMD2(impact.x + cos(angle) * disk * spread,
                                   impact.y + (collision ? sin(angle) : abs(sin(angle))) * disk * verticalSpread)
                let lobe = floor(r.x * 9) / 9 * .pi * 2
                let launch = kind == 2 ? lobe + (r.y - 0.5) * 0.35 : angle
                let direction = SIMD2(cos(launch), collision ? sin(launch) : abs(sin(launch)) * 0.85 + 0.12)
                let speed = (kind == 2 ? 0.10 + r.y * 0.23 : kind == 3 ? 0.20 + r.y * 0.44 : 0.16 + r.y * 0.60) * power
                let size: Float = kind == 2 ? (0.014 + r.w * 0.023) * (0.7 + scale * 1.6)
                    : kind == 3 ? (0.003 + pow(r.z, 3) * 0.009) * (0.65 + scale)
                    : 0.0007 + r.w * 0.002
                let life = star.cloudLife * (kind == 2 ? 0.42 + r.z * 0.30 : kind == 3 ? 0.20 + r.z * 0.30 : 0.25 + r.z * 0.52)
                let hueShift = SIMD3<Float>(1, 0.72 + r.w * 0.28, 0.65 + r.y * 0.35)
                particles.append(Particle(position: SIMD4(origin.x, origin.y, direction.x * speed, direction.y * speed),
                    life: SIMD4(size, 0, life, r.y * 100), color: SIMD4(color * hueShift, Float(kind)),
                    owner: SIMD4(Float(star.id), 1, depth, 0)))
            }
        }
    }

    private func random4() -> SIMD4<Float> {
        serial += 1
        let n = Double(serial) + seed * 1000
        return SIMD4(Float(hash(n)), Float(hash(n + 713.3)), Float(hash(n + 91.7)), Float(hash(n + 1321.1)))
    }
}
