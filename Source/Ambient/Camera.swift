import simd

/// Fixed world camera shared numerically with Noctiluca.metal; tremors affect only the final composition.
/// One projected unit is image height.
enum SceneCamera {
    static let origin = SIMD3<Float>(0, 0.42, 0)
    static let forward = SIMD3<Float>(0, 0.28, -0.96)
    static let up = SIMD3<Float>(0, -forward.z, forward.y)

    static func world(_ point: SIMD2<Float>, distance: Float) -> SIMD3<Float> {
        origin + forward * distance + SIMD3(point.x * distance, 0, 0) + up * (point.y * distance)
    }

    static func project(_ point: SIMD3<Float>) -> SIMD2<Float> {
        let relative = point - origin
        let distance = simd_dot(relative, forward)
        return SIMD2(relative.x, simd_dot(relative, up)) / distance
    }

    /// Presentation-only displacement in image-height units. Scene ages freeze the tremor on pause.
    /// Ground impulses superpose, then saturate at four thousandths of the image height.
    static func shake(for bodies: [BodyGPU]) -> SIMD2<Float> {
        var displacement = SIMD2<Float>.zero
        for body in bodies where body.contact.w > 0.5 && body.impactEffects.z > 0 {
            let age = body.shape.z
            guard age >= 0 && age < 0.85 else { continue }
            let envelope = pow(1 - age / 0.85, 3) * (1 - exp(-age * 90))
            let phase = body.color.w * 2.399963
            let oscillation = SIMD2(
                sin(age * 83 + phase) * 0.65 + sin(age * 139) * 0.35,
                cos(age * 107 + phase * 0.7) * 0.7 + sin(age * 157) * 0.3)
            displacement += oscillation * (0.0036 * body.impactEffects.z * envelope)
        }
        let length = simd_length(displacement)
        return length > 0.004 ? displacement * (0.004 / length) : displacement
    }
}
