import Foundation

/// A birth-time composition is immutable, so later direction changes never variation a body midflight.
struct ArrivalComposition {
    let hue: Float
    let slope: Float
    let speedScale: Float
}

/// Seeded irregular control points replace periodic density waves; no fixed order of scene moods.
struct SceneDirector {
    struct Snapshot: Equatable {
        let activity: Double
        let hue: Float
        let heading: Float

        func arrival(id: Int, seed: Double) -> ArrivalComposition {
            let key = Double(id) * 17.31 + seed
            let accent = hash(key + 71)
            // Keep a theme without confining the scene to a single narrow hue band.
            let offset: Double =
                accent < 0.45
                ? (hash(key + 13) - 0.5) * 0.18
                : accent < 0.8
                    ? (hash(key + 19) < 0.5 ? -1.0 / 3 : 1.0 / 3) + (hash(key + 29) - 0.5) * 0.08
                    : 0.5 + (hash(key + 29) - 0.5) * 0.08
            let color = Double(hue) + offset
            let independent = Float(hash(key + 7) * 2 - 1)
            let direction = hash(key + 41) < 0.32 ? independent : heading * 0.65 + independent * 0.35
            return ArrivalComposition(
                hue: Float(color - floor(color)),
                slope: direction * tan(Float.pi * 50 / 180),
                speedScale: Float(0.9 + activity * 0.17 + hash(key + 53) * 0.15))
        }

        func ordinaryDelay(id: Int, seed: Double) -> Double {
            0.9 + hash(Double(id) * 6.71 + seed + 3) * (1.9 + pow(1 - activity, 2) * 7)
        }

        func bolideDelay(id: Int, seed: Double) -> Double {
            12 + hash(Double(id) * 9.31 + seed) * 10 + (1 - activity) * 3
        }
    }

    private struct Point {
        let activity: Double
        let hue: Double
        let heading: Double
    }
    private let seed: Double
    private var index = 0
    private var start: Double
    private var end: Double
    private var from: Point
    private var target: Point
    private var recoveryStart = -Double.infinity
    private var recoveryEnd = -Double.infinity

    init(seed: Double, time: Double) {
        self.seed = seed
        start = time
        end = time + 6 + hash(seed + 413) * 10
        from = Point(
            activity: 0.55 + hash(seed + 61) * 0.35, hue: hash(seed + 19), heading: hash(seed + 73) * 2 - 1)
        target = Self.point(index: 1, seed: seed)
    }

    private static func point(index: Int, seed: Double) -> Point {
        let key = Double(index) * 43.17 + seed
        let choice = hash(key + 11)
        let activity =
            choice < 0.25
            ? 0.22 + hash(key + 23) * 0.16
            : choice > 0.55 ? 0.85 + hash(key + 23) * 0.15 : 0.55 + hash(key + 23) * 0.25
        return Point(activity: activity, hue: hash(key + 37), heading: hash(key + 59) * 2 - 1)
    }

    /// Scene-time only; repeated paused samples and different frame cadences yield identical direction.
    mutating func sample(at time: Double) -> Snapshot {
        while time >= end {
            start = end
            from = target
            index += 1
            target = Self.point(index: index + 1, seed: seed)
            end = start + 6 + hash(Double(index) * 67.31 + seed + 413) * 10
        }
        let t = clamp((time - start) / (end - start), 0, 1)
        let blend = t * t * (3 - 2 * t)
        var hueDelta = target.hue - from.hue
        hueDelta -= floor(hueDelta + 0.5)
        let color = from.hue + hueDelta * blend
        let recovery = time < recoveryEnd ? (recoveryEnd - time) / max(0.001, recoveryEnd - recoveryStart) : 0
        return Snapshot(
            activity: clamp(
                from.activity + (target.activity - from.activity) * blend - recovery * 0.18, 0, 1),
            hue: Float(color - floor(color)),
            heading: Float(from.heading + (target.heading - from.heading) * blend))
    }

    /// A large event briefly lowers arrival pressure; it does not schedule a mandatory next act.
    mutating func noteClimax(at time: Double, id: Int) {
        recoveryStart = time
        recoveryEnd = time + 1.5 + hash(Double(id) * 13.7 + seed) * 2
    }
}
