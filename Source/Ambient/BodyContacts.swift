import Foundation
import simd

/// Fixed contact geometry anchors an impact while detached material disperses independently.
struct BodyContact {
    let age: Double
    let center: SIMD3<Float>
    let point: SIMD3<Float>
}

/// First contact along a relative segment; detects fast bodies that cross between frames.
func sweptContact(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float) -> Float? {
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
func resolveBodyCollisions(bodies: inout [SceneBody], from before: Double, to time: Double, aspect: Float) {
    var contacts: [(time: Double, a: Int, b: Int, point: SIMD3<Float>)] = []
    for a in bodies.indices where bodies[a].collision == nil && !bodies[a].impactEmitted {
        for b in bodies.indices where b > a && bodies[b].collision == nil && !bodies[b].impactEmitted {
            let first = bodies[a]
            let second = bodies[b]
            let start = max(before, first.birth, second.birth)
            let end = min(time, first.birth + first.impactAge, second.birth + second.impactAge)
            guard end > start else { continue }
            let a0 = first.worldPosition(age: start - first.birth, aspect: aspect)
            let b0 = second.worldPosition(age: start - second.birth, aspect: aspect)
            let a1 = first.worldPosition(age: end - first.birth, aspect: aspect)
            let b1 = second.worldPosition(age: end - second.birth, aspect: aspect)
            let r1 = first.worldRadius * 0.9
            let r2 = second.worldRadius * 0.9
            guard let t = sweptContact(from: a0 - b0, to: a1 - b1, radius: r1 + r2) else { continue }
            let ca = a0 + (a1 - a0) * t
            let cb = b0 + (b1 - b0) * t
            let point = (ca * r2 + cb * r1) / (r1 + r2)
            let projected = SceneCamera.project(point)
            guard abs(projected.x) <= aspect / 2 && (-0.5...0.5).contains(projected.y), point.y > 0 else {
                continue
            }
            contacts.append((start + (end - start) * Double(t), a, b, point))
        }
    }
    for contact in contacts.sorted(by: { $0.time < $1.time }) {
        guard bodies[contact.a].collision == nil && bodies[contact.b].collision == nil else { continue }
        let a = bodies[contact.a]
        let b = bodies[contact.b]
        let victim =
            a.worldRadius == b.worldRadius
            ? (a.id > b.id ? contact.a : contact.b)
            : (a.worldRadius < b.worldRadius ? contact.a : contact.b)
        let age = contact.time - bodies[victim].birth
        let center = bodies[victim].worldPosition(age: age, aspect: aspect)
        bodies[victim].collision = BodyContact(age: age, center: center, point: contact.point)
    }
}
