/// Material identity encoded in ParticleGPU.color.w; values are shared with Noctiluca.metal.
enum ParticleKind: Float, CaseIterable {
    case vapor = 0
    case ember = 1
    case impactGas = 2
    case rockFragment = 3
    case soilDust = 4
    case ionTrail = 5
    case plasmaTrail = 6
    case regolithGrain = 7

    var isGas: Bool { self == .impactGas || self == .soilDust }
}

/// Dynamics state encoded in ParticleGPU.owner.y. Material identity remains unchanged after landing.
enum ParticleDynamics: Float, CaseIterable {
    case wakeSpark = -1
    case wake = 0
    case ballistic = 1
    case bounced = 1.5
    case settled = 2
}
