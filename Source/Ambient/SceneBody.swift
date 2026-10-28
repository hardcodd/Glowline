import Foundation
import simd

/// One incoming body: immutable birth/model parameters plus resolved contacts and emission progress.
/// World-space flight is shared by every model and is independent of display cadence.
struct SceneBody {
    let id: Int
    let birth: Double
    /// Seeded size parameter; worldRadius converts it to the actual scene-space collision envelope.
    let radius: Float
    /// Vertical travel coefficient; physicalScale converts it to world-space velocity.
    let speed: Float
    let variation: Float
    let entryLane: Float
    let hue: Float
    let depthScale: Float
    let model: BodyModel
    private let depthDirection: Float
    private let directedSlope: Float?
    var collision: BodyContact?
    var groundContact: BodyContact?
    var impactEmitted = false
    var pendingTrailParticles: Double = 0

    init(
        id: Int, birth: Double, seed: Double, depthScale: Float? = nil,
        depthDirection: Float? = nil, composition: ArrivalComposition? = nil,
        arrival: BodyArrival = .sporadic()
    ) {
        self.id = id
        self.birth = birth
        let shower = arrival.showerMember
        directedSlope = composition?.slope
        let size = hash(Double(id) * 8.17 + seed)
        let candidate = 0.035 + 0.23 * pow(size, 6)
        switch arrival {
        case .shower:
            radius = Float(0.022 + size * 0.028)
        case .bolide:
            radius = Float(0.11 + size * 0.04)
        case .sporadic(let allowMassive):
            // An occupied large-body slot reduces size without discarding the hot arrival.
            radius = Float(!allowMassive && candidate >= 0.16 ? 0.13 + size * 0.025 : candidate)
        }
        model = BodyModel(arrival: arrival, crustFraction: Self.crustFraction(radius: radius))
        variation = Float(hash(Double(id) * 3.1 + seed))
        entryLane = Float(hash(Double(id) * 5.7 + seed))
        hue =
            shower.map { $0.hue + (Float(size) - 0.5) * $0.hueSpread }
            ?? composition?.hue ?? Float(Double(id) * 0.381966 + seed * 0.071)
        let depth = Float(hash(Double(id) * 17.43 + seed))
        self.depthScale =
            depthScale
            ?? (depth < 0.4
                ? 1 + depth * 0.5
                : 1.4 + pow((depth - 0.4) / 0.6, 1.1) * 3.6)
        self.depthDirection =
            depthDirection ?? (shower != nil ? 0.12 : Float(hash(Double(id) * 23.13 + seed) * 2 - 1))
        let baseSpeed = Float(0.062) + 0.0012 / (radius * radius)
        // Judge slowness in the image: a small distant body can otherwise crawl despite high world speed.
        // Freeze pacing at birth; distant arrivals need a floor in projected image-height units.
        let visibleSpeed =
            baseSpeed * (baseSpeed / self.depthScale <= 0.12 ? 1.21 : 1)
            * (Self.crustFraction(radius: radius) <= 0.25 ? 1.1 : 1)
        let pacing = composition?.speedScale ?? 1
        let minimumSpeed: Float = (Self.crustFraction(radius: radius) <= 0.25 ? 1.1 : 0.45) * max(1, pacing)
        switch model {
        case .showerMeteor:
            speed = self.depthScale * Float(1.55 + size * 1.0)
        case .bolide:
            speed = self.depthScale * 4.8
        case .meteor, .superheatedAsteroid:
            speed = max(visibleSpeed * 1.4 * pacing, self.depthScale * minimumSpeed)
        }
    }

    /// Crust fraction: small asteroids are rocky, massive arrivals are molten beneath a thin crust.
    var crustFraction: Float {
        Self.crustFraction(radius: radius)
    }

    private static func crustFraction(radius: Float) -> Float {
        let t = clamp((radius - 0.065) / 0.085, 0, 1)
        return 1 - t * t * (3 - 2 * t)
    }

    var sizeFraction: Float { clamp((radius - 0.035) / 0.23, 0, 1) }
    /// Only massive bodies and bolides transfer a visible ground impulse; contact is checked separately.
    var impactShakeStrength: Float { model.isBolide ? 1 : radius >= 0.16 ? 0.45 + sizeFraction * 0.3 : 0 }
    /// Superheated asteroids melt into lakes; ordinary meteors, bolides and showers leave dry debris.
    var makesLavaLake: Bool { model.groundImpact == .lavaLake }
    var impactHeat: Float { makesLavaLake ? 0.9 : 0 }
    var trailStyle: TrailStyle { crustFraction <= 0.25 ? .plasma : (id % 3 == 0 ? .comet : .meteor) }
    var approachGlowDuration: Float { 0.25 + 0.684 * sizeFraction }
    /// Physical body dimensions stay independent of camera placement.
    var physicalScale: Float { 2.4 + Float(hash(Double(id) * 11.19 + Double(variation))) * 4.2 }
    var referenceDepth: Float { physicalScale * depthScale }
    var worldRadius: Float { physicalScale * radius / sqrt(1 + radius * radius) }
    var apparentRadius: Float { worldRadius / sqrt(referenceDepth * referenceDepth - worldRadius * worldRadius) }
    func apparentRadius(at point: SIMD3<Float>) -> Float {
        let depth = simd_dot(point - SceneCamera.origin, SceneCamera.forward)
        return worldRadius / sqrt(max(0.000001, depth * depth - worldRadius * worldRadius))
    }
    var screenSpeed: Float { speed * physicalScale / referenceDepth }
    var entryLeadDistance: Float {
        if model.isBolide || model.showerMember != nil { return screenSpeed * 0.18 }
        // A receding body needs no long invisible lead-in that would constrain its useful depth travel.
        // Faster hot asteroids keep the same spatial lead-in instead of spending longer offscreen.
        let leadSpeed = crustFraction <= 0.25 ? min(screenSpeed, 0.45) : screenSpeed
        return depthDirection < 0
            ? leadSpeed * max(1.8, approachGlowDuration)
            : max(apparentRadius * 4, leadSpeed * max(1.8, approachGlowDuration))
    }
    var entryAge: Double { Double(entryLeadDistance / screenSpeed) }
    var groundAge: Double {
        let groundY =
            (worldRadius - SceneCamera.origin.y - SceneCamera.forward.y * referenceDepth)
            / (SceneCamera.up.y * referenceDepth)
        return Double((0.5 + apparentRadius + entryLeadDistance - groundY) / screenSpeed)
    }
    var impactAge: Double { collision?.age ?? groundContact?.age ?? groundAge }
    /// World-Z drift changes perspective. Clearance limits are set once for the entire straight flight.
    var depthVelocity: Float {
        let scale = physicalScale * speed
        let lateralLimit = tan(Float.pi / 3) * SceneCamera.up.y
        let zLimit = sqrt(lateralLimit * lateralLimit - slope * slope) * scale
        let requested = clamp(
            depthDirection * 1.15 * scale,
            SceneCamera.up.z * scale - zLimit, SceneCamera.up.z * scale + zLimit)
        let projection = abs(SceneCamera.forward.z)
        let flight = Float(groundAge - entryAge)
        let burstClearance = referenceDepth - max(referenceDepth * 0.4, worldRadius * 1.6 + 0.05)
        // Keep both ends of a steep diagonal visible even at the narrowest supported 16:9 aspect.
        let relativeRadius = worldRadius / referenceDepth
        let contactExtent = relativeRadius / sqrt(1 - pow(relativeRadius / 0.5, 2))
        // Leave room below the contact point for the crater and ejected debris.
        let groundClearance = (2.6 + SceneCamera.forward.y * worldRadius) / referenceDepth
        let minimumDepth = max(
            0.5, groundClearance,
            (abs(slope) * flight * screenSpeed
                + (apparentRadius + contactExtent) * 0.7) / (Float(16) / 9 * 0.5) - 1)
        let toward = min(
            referenceDepth * (1 - minimumDepth) / (projection * flight),
            burstClearance / (projection * flight))
        let birthClearance = referenceDepth - max(referenceDepth * 0.35, worldRadius * 1.5 + 0.05)
        let away = birthClearance / (projection * Float(entryAge))
        return clamp(requested, -away, toward)
    }
    var entryVelocity: SIMD3<Float> {
        (SIMD3(slope, 0, 0) - SceneCamera.up) * (physicalScale * speed) + SIMD3(0, 0, depthVelocity)
    }
    /// Equal-density spheres retain physical mass independent of camera placement.
    var mass: Float { 4 / 3 * .pi * worldRadius * worldRadius * worldRadius * 3.2 }
    /// Work against dry-soil pressure plus inertial drag stops the normal impact momentum.
    /// Scene units are artistic; depth comes from kinetic energy / resisting force, not a sink tween.
    var groundPenetration: Float {
        let normalSpeed = max(0, -entryVelocity.y)
        let area = Float.pi * worldRadius * worldRadius
        let resistance = area * (110 + 1.8 * normalSpeed * normalSpeed)
        return 0.5 * mass * normalSpeed * normalSpeed / max(0.001, resistance)
    }
    var groundStopTime: Float { 2 * groundPenetration / max(0.001, -entryVelocity.y) }

    var disintegrationDuration: Float {
        groundContact != nil ? 0.055 + 0.035 * sizeFraction : 0.18 + 0.15 * sizeFraction
    }
    var cloudLifetime: Float { 4.8 + 0.423 * sizeFraction }
    var trailLifetime: Float { 2.5 + 1.119 * sizeFraction }
    var duration: Double {
        // Shower material lives independently on the GPU; release the source slot after its flash fades.
        let remnants: Float = model.showerMember == nil ? max(8, cloudLifetime, trailLifetime) : 3
        // A later arrival can enter an existing pit two units below the original plane.
        let allowance =
            groundContact == nil && collision == nil ? max(remnants, 2 / -entryVelocity.y + 1) : remnants
        return impactAge + Double(allowance)
    }
    var slope: Float {
        if let shower = model.showerMember { return shower.slope + (variation - 0.5) * 0.05 }
        if let directedSlope { return directedSlope }
        let direction = variation * 2 - 1
        // Most arrivals remain calm; occasional opposite diagonals create crossings and contacts.
        let angle: Float =
            abs(direction) > 0.90
            ? .pi * 50 / 180
            : abs(direction) > 0.72 ? .pi * 34 / 180 : .pi / 15
        return direction * tan(angle)
    }

    func position(age: Double, aspect: Float) -> SIMD2<Float> {
        SceneCamera.project(worldPosition(age: age, aspect: aspect))
    }

    private func planarPosition(age: Double, aspect: Float) -> SIMD2<Float> {
        let contactDepth = referenceDepth + SceneCamera.forward.z * depthVelocity * Float(groundAge - entryAge)
        let perspective = contactDepth / referenceDepth
        let contactRadius = worldRadius / sqrt(contactDepth * contactDepth - worldRadius * worldRadius)
        let drift = slope * Float(groundAge - entryAge) * screenSpeed
        let halfEntry = aspect / 2 - apparentRadius * 0.7
        let halfContact = (aspect / 2 - contactRadius * 0.7) * perspective
        // Intersect entry/contact coverage in world coordinates before choosing an entry lane.
        let low = max(-halfEntry, -halfContact - drift)
        let high = min(halfEntry, halfContact - drift)
        let preferred = (entryLane - 0.5) * max(0.1, aspect - apparentRadius * 3.4) - drift * 0.5
        let entry = clamp(preferred, low, high)
        let travel = Float(max(0, age)) * screenSpeed
        return SIMD2(entry + slope * (travel - entryLeadDistance), 0.5 + apparentRadius + entryLeadDistance - travel)
    }

    /// Incoming flight loses momentum against dry-ground resistance; detached pieces evolve independently.
    func worldPosition(age: Double, aspect: Float) -> SIMD3<Float> {
        if let collision, age >= collision.age { return collision.center }
        if let groundContact, age >= groundContact.age {
            let stop = max(0.00001, groundStopTime)
            let t = min(Float(age - groundContact.age), stop)
            return groundContact.center + entryVelocity * (t * (1 - 0.5 * t / stop))
        }
        let airAge = max(0, age)
        var center = SceneCamera.world(planarPosition(age: airAge, aspect: aspect), distance: referenceDepth)
        center.z += depthVelocity * Float(airAge - entryAge)
        return center
    }
}
