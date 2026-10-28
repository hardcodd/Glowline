import Foundation

/// Scene-time scheduling only; SceneSimulation owns bodies and the GPU owns their detached material.
struct MeteorShower {
    struct Member {
        let event: Int
        let slope: Float
        let hue: Float
        var hueSpread: Float = 0.62
    }

    private let seed: Double
    private var nextStart: Double
    private var end: Double = -.infinity
    private var nextArrival: Double = .infinity
    private var event = 0
    private var member = Member(event: 0, slope: 0, hue: 0)

    init(seed: Double, time: Double) {
        self.seed = seed
        nextStart = time + 8 + hash(seed + 143.8) * 4
    }

    func isActive(at time: Double) -> Bool { time < end }

    /// Capacity pressure drops individual meteors rather than releasing a delayed burst later.
    /// Disabled births abandon the wave and require a fresh quiet lead-in on resume.
    mutating func arrivals(
        at time: Double, enabled: Bool, capacity: Int,
        activity: Double = 0.7, tone: Float? = nil, heading: Float? = nil
    ) -> [(Double, Member)] {
        guard enabled else {
            end = -.infinity
            nextArrival = .infinity
            nextStart = max(nextStart, time + 8)
            return []
        }
        if time >= nextStart {
            if activity < 0.18 {
                nextStart = time + 3 + hash(nextStart + seed) * 4
                return []
            }
            event += 1
            let random = hash(Double(event) * 31.7 + seed)
            member = Member(
                event: event,
                slope: (heading.map { abs($0) > 0.15 ? ($0 < 0 ? -1 : 1) : (random < 0.5 ? -1 : 1) }
                    ?? (random < 0.5 ? -1 : 1)) * Float(0.4 + random * 0.3),
                hue: tone ?? Float(hash(Double(event) * 47.3 + seed)))
            nextArrival = time
            end = time + 6 + hash(Double(event) * 29.1 + seed) * 2
            nextStart = end + 24 + hash(Double(event) * 71.9 + seed) * 24 + (1 - activity) * 4
        }
        var result: [(Double, Member)] = []
        while nextArrival <= time && nextArrival < end {
            if result.count < capacity { result.append((nextArrival, member)) }
            nextArrival += 0.22 + hash(nextArrival * 9.7 + seed) * 0.13
        }
        return result
    }
}
