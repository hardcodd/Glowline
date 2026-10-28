/// A scheduling request. Sporadic arrivals choose their physical model once their seeded size is known.
enum BodyArrival {
    case sporadic(allowMassive: Bool = true)
    case bolide
    case shower(MeteorShower.Member)

    var showerMember: MeteorShower.Member? {
        if case .shower(let member) = self { return member }
        return nil
    }
}

/// Physical identity is fixed at birth; trail appearance does not determine the impact outcome.
/// The associated shower member carries its event, shared radiant and color composition together.
enum BodyModel {
    case meteor
    case superheatedAsteroid
    case bolide
    case showerMeteor(MeteorShower.Member)

    init(arrival: BodyArrival, crustFraction: Float) {
        switch arrival {
        case .bolide: self = .bolide
        case .shower(let member): self = .showerMeteor(member)
        case .sporadic: self = crustFraction <= 0.25 ? .superheatedAsteroid : .meteor
        }
    }

    var showerMember: MeteorShower.Member? {
        if case .showerMeteor(let member) = self { return member }
        return nil
    }

    var isBolide: Bool {
        if case .bolide = self { return true }
        return false
    }

    var groundImpact: GroundImpactOutcome {
        switch self {
        case .superheatedAsteroid: return .lavaLake
        case .meteor, .bolide, .showerMeteor: return .fragments
        }
    }
}

/// Body material either becomes a cooling pool or detached solid pieces; soil ejecta occur in both cases.
enum GroundImpactOutcome {
    case fragments
    case lavaLake
}

/// A visual wake family, independent of the body's physical identity and ground impact.
enum TrailStyle { case plasma, comet, meteor }
