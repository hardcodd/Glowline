import CoreGraphics
import Foundation
import simd

func runAmbientMotionTests() {
    runBodyModelTests()
    runSceneDirectionTests()
    runMeteorShowerTests()
    runImpactShakeTests()
    let events = (0..<10000).map { SceneBody(id: $0, birth: Double($0), seed: 13.7) }
    let bolide = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0, arrival: .bolide)
    precondition(bolide.screenSpeed > events.map(\.screenSpeed).max()! * 2)
    precondition(bolide.groundAge - bolide.entryAge < 0.3)
    for cadence in [30.0, 60.0, 144.0] {
        let flight = SceneSimulation(seed: 2, bodies: [bolide], time: bolide.entryAge)
        var fragments = 0
        var grains = 0
        for _ in 0..<Int(cadence * 2) {
            let frame = flight.advance(delta: 1 / cadence, aspect: 3440 / 1440, palette: 0, births: false)
            fragments += frame.newParticles.filter { $0.color.w == 3 }.count
            grains += frame.newParticles.filter { $0.color.w == 7 }.count
            precondition(frame.newParticles.count <= 4096)
            precondition(frame.bodies.first?.impactEffects.x == 1)
            precondition(frame.bodies.first?.flight.w == bolide.screenSpeed,
                         "Incoming fire must receive visible speed independently of crust heat")
        }
        precondition(
            flight.terrain.impactCount == 1 && fragments > 80 && flight.terrain.meltPools.isEmpty,
            "Rocky bolides must hit once between frames, eject fragments and never create lava")
        precondition(grains > 150, "Ground impact must throw solid regolith grains as well as dust")
    }
    for style in [TrailStyle.plasma, .comet, .meteor] {
        let body = events.first { $0.trailStyle == style }!
        let sample = SceneSimulation(
            seed: 2, bodies: [body],
            time: body.birth + body.entryAge + (body.groundAge - body.entryAge) * 0.35)
        let frame = sample.advance(delta: 0.1, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(
            frame.newParticles.contains { $0.color.w == (style == .plasma ? 6 : 5) },
            "Every tail family needs an emissive stream as well as ordinary smoke")
        precondition(
            frame.newParticles.contains { $0.color.w == 0 } && frame.newParticles.contains { $0.color.w == 1 }
        )
        precondition(
            frame.newParticles.filter { $0.color.w == 1 }.allSatisfy { $0.owner.y < 0 },
            "Tail sparks need wake dynamics, distinct from ballistic impact debris")
        precondition(
            frame.newParticles.allSatisfy { particle in
                let velocity = SIMD3(particle.position.z, particle.position.w, particle.owner.w)
                return particle.life.z > 0 && particle.life.z <= 6
                    && simd_dot(velocity, -body.entryVelocity) > 0
                    && (particle.color.w != 1 || velocity.y > body.entryVelocity.y)
            }, "Airborne tail material must leave the rear hemisphere with bounded lifetime")
        let landing = SceneSimulation(seed: 2, bodies: [body], time: body.birth + body.groundAge - 0.5)
        var sawImpact = false
        for _ in 0..<120 {
            let sample = landing.advance(delta: 1 / 60, aspect: 3440 / 1440, palette: 0, births: false)
            if sample.bodies.first?.shape.z ?? -1 >= 0 { sawImpact = true }
        }
        precondition(sawImpact && landing.terrain.impactCount == 1)
        let after = landing.advance(delta: 0.1, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(
            after.newParticles.isEmpty,
            "Broken bodies must stop new emission without erasing the detached wake")
    }
    for body in events {
        precondition(
            body.screenSpeed >= 0.45 - 0.000001,
            "Ordinary arrivals must have a brisk minimum visible entry speed")
        let previous =
            (Float(0.062) + 0.0012 / (body.radius * body.radius))
            * (body.crustFraction <= 0.25 ? 1.1 : 1)
        precondition(
            body.speed >= previous * 1.39,
            "The ordinary distribution must speed up, including already fast bodies")
    }
    for body in events where body.crustFraction <= 0.25 {
        precondition(
            body.screenSpeed >= 1.1 - 0.000001,
            "Superheated asteroid replacements must not retain slow visible pacing")
    }
    let approaching = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 1)
    let receding = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: -1)
    let approachingContact = approaching.worldPosition(age: approaching.groundAge, aspect: 3440 / 1440)
    let recedingContact = receding.worldPosition(age: receding.groundAge, aspect: 3440 / 1440)
    precondition(
        approaching.apparentRadius(at: approachingContact) > approaching.apparentRadius * 1.6,
        "Strong approaches must produce an unmistakable perspective increase")
    precondition(
        receding.apparentRadius(at: recedingContact) < receding.apparentRadius * 0.65,
        "Strong receding flights must visibly shrink before ground contact")
    let near = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    let far = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 4, depthDirection: 0)
    precondition(near.worldRadius == far.worldRadius && near.mass == far.mass)
    precondition(
        -far.entryVelocity.y >= -near.entryVelocity.y,
        "Distant bodies may move faster to preserve visible pacing without changing mass or size")
    precondition(far.apparentRadius < near.apparentRadius * 0.3)
    let nearContact = near.worldPosition(age: near.groundAge, aspect: 3440 / 1440)
    let farContact = far.worldPosition(age: far.groundAge, aspect: 3440 / 1440)
    precondition(farContact.z < nearContact.z * 3)
    precondition(SceneCamera.project(farContact).y < SceneCamera.project(nearContact).y)
    for family in [events.filter { $0.crustFraction == 1 }, events.filter { $0.crustFraction <= 0.25 }] {
        precondition(
            family.contains { $0.entryVelocity.z > 0 }, "Bodies must be able to fly toward the screen")
        precondition(
            family.contains { $0.entryVelocity.z < 0 }, "Bodies must be able to fly into the distance")
        precondition(family.contains { $0.depthVelocity > 0 } && family.contains { $0.depthVelocity < 0 })
        precondition(
            family.contains { abs($0.slope) > tan(Float.pi * 40 / 180) },
            "Every family must include the newly widened lateral angles")
        precondition(family.filter { $0.depthScale < 1.3 }.count > family.count / 3)
        precondition(
            family.filter { $0.depthScale > 3.5 }.count > family.count / 5,
            "Both meteors and bodies must include genuinely distant arrivals")
    }
    precondition(events.contains { $0.crustFraction == 1 })
    precondition(events.contains { $0.crustFraction == 0 })
    let superheated = events.filter { $0.crustFraction <= 0.25 }
    let meteors = events.filter { $0.crustFraction == 1 }
    precondition(
        (1200...1700).contains(superheated.count),
        "Superheated asteroids need a modest increase over the original rare distribution")
    precondition(meteors.count > superheated.count)
    for body in superheated where body.radius >= 0.16 {
        let limited = SceneBody(
            id: body.id, birth: body.birth, seed: 13.7, arrival: .sporadic(allowMassive: false))
        precondition(
            limited.radius < 0.16 && limited.crustFraction <= 0.25,
            "An occupied large-body slot must preserve the superheated arrival as a medium asteroid")
    }
    for family in [superheated, events.filter { $0.radius >= 0.20 }] {
        let diagonal = family.filter { abs($0.slope) > tan(Float.pi / 9) }
        precondition(diagonal.count > family.count / 5)
        precondition(
            diagonal.contains { $0.slope < 0 } && diagonal.contains { $0.slope > 0 },
            "Asteroids of every size must support pronounced angles in both directions")
    }
    for body in events {
        precondition((0...1).contains(body.crustFraction))
        if body.radius >= 0.16 { precondition(body.crustFraction == 0) }
        if body.radius <= 0.065 { precondition(body.crustFraction == 1) }
    }
    precondition(events.allSatisfy { (0.035...0.265).contains($0.radius) })
    precondition(events.contains { $0.radius > 0.25 })
    let sorted = events.sorted { $0.radius < $1.radius }
    for pair in zip(sorted, sorted.dropFirst()) where pair.1.radius - pair.0.radius > 0.000001 {
        precondition(pair.0.crustFraction >= pair.1.crustFraction)
        precondition(pair.0.approachGlowDuration < pair.1.approachGlowDuration)
        precondition(pair.0.cloudLifetime < pair.1.cloudLifetime)
    }
    for body in events {
        for aspect: Float in [16 / 9, 3440 / 1440, 32 / 9] {
            let a = body.position(age: body.entryAge, aspect: aspect)
            let b = body.position(age: body.groundAge, aspect: aspect)
            let world = body.worldPosition(age: body.groundAge, aspect: aspect)
            precondition(
                abs(world.y - body.worldRadius) < 0.0001, "Lower limb must touch the nominal ground plane")
            let contact = body.worldPosition(age: body.groundAge, aspect: aspect)
            let dt: Double = 0.005
            precondition(
                simd_length(SceneCamera.project(SceneCamera.world(a, distance: body.referenceDepth)) - a) < 0.0001)
            precondition(abs(body.slope) <= tan(Float.pi * 50 / 180) + 0.0001)
            let velocity = body.entryVelocity
            precondition(
                simd_length(SIMD2(velocity.x, velocity.z)) / -velocity.y <= tan(Float.pi / 3) + 0.0001)
            let entry = body.worldPosition(age: body.entryAge, aspect: aspect)
            let flightAge = (body.entryAge + body.groundAge) * 0.5
            let flightVelocity =
                (body.worldPosition(age: flightAge + dt, aspect: aspect)
                    - body.worldPosition(age: flightAge - dt, aspect: aspect)) / Float(2 * dt)
            precondition(
                simd_length(flightVelocity - velocity) < 0.003,
                "Depth flight must be a straight world-space path before touching the terrain")
            let startDepth = simd_dot(entry - SceneCamera.origin, SceneCamera.forward)
            let contactDepth = simd_dot(contact - SceneCamera.origin, SceneCamera.forward)
            let groundFoot = contact - SIMD3<Float>(0, body.worldRadius, 0)
            precondition(
                SceneCamera.project(groundFoot).y > -0.48,
                "Stronger approaches must keep the ground contact inside the bottom edge")
            let birthDepth = simd_dot(
                body.worldPosition(age: 0, aspect: aspect) - SceneCamera.origin, SceneCamera.forward)
            let birthCenter = body.worldPosition(age: 0, aspect: aspect)
            precondition(
                SceneCamera.project(birthCenter).y - body.apparentRadius(at: birthCenter) > 0.5,
                "A depth trajectory must arrive from outside the frame, not pop into the air")
            precondition(
                min(birthDepth, contactDepth) >= max(body.referenceDepth * 0.349, body.worldRadius * 1.2),
                "Depth flight must keep its incoming sphere safely in front of the camera")
            if body.depthVelocity > 0.001 {
                precondition(
                    contactDepth < startDepth
                        && body.apparentRadius(at: contact) > body.apparentRadius(at: entry))
            } else if body.depthVelocity < -0.001 {
                precondition(
                    contactDepth > startDepth
                        && body.apparentRadius(at: contact) < body.apparentRadius(at: entry))
            }
            precondition(abs(a.x) + body.apparentRadius * 0.7 <= aspect / 2 + 0.0001)
            precondition(abs(b.x) + body.apparentRadius(at: contact) * 0.7 <= aspect / 2 + 0.0001)

        }
    }
    // Swept contacts must catch fast meteors between frames and preserve the larger body.
    precondition(sweptContact(from: SIMD3<Float>(0, 2, 0), to: SIMD3<Float>(0, -2, 0), radius: 0.2) != nil)
    precondition(
        sweptContact(from: SIMD3<Float>(0, 2, 1), to: SIMD3<Float>(0, -2, 1), radius: 0.2) == nil,
        "Projected crossings at different depths must not collide")
    precondition(sweptContact(from: .zero, to: .zero, radius: 0.2) == 0)
    let large = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    let aspect: Float = 3440 / 1440
    let entrySim = SceneSimulation(seed: 1, bodies: [large], time: large.groundAge - 0.5)
    var impactFrame: SimulationFrame?
    for _ in 0..<120 {
        let sample = entrySim.advance(delta: 1 / 60, aspect: aspect, palette: 0, births: false)
        if sample.newParticles.contains(where: { $0.color.w == 4 }) { impactFrame = sample }
    }
    precondition(entrySim.bodies[0].impactEmitted && entrySim.bodies[0].groundContact != nil)
    precondition(entrySim.terrain.impactCount == 1 && impactFrame != nil)
    precondition(impactFrame!.newParticles.contains { $0.color.w == 4 }, "Ground impact must eject sand dust")
    let resolved = entrySim.bodies[0].groundContact!
    precondition(
        abs(resolved.center.y - large.worldRadius - resolved.point.y) < 0.0001,
        "The lower limb must touch the current sandy surface before excavation")
    let stopped = entrySim.bodies[0].worldPosition(age: resolved.age + 10, aspect: aspect)
    precondition(
        abs(stopped.y - resolved.center.y + large.groundPenetration) < 0.00001,
        "Dry ground must stop the impact at its energy-limited depth")
    entrySim.terrain.advance(delta: 8)
    let permanent = entrySim.terrain.cells
    for _ in 0..<600 { _ = entrySim.advance(delta: 1 / 60, aspect: aspect, palette: 0, births: false) }
    precondition(
        entrySim.bodies.isEmpty && entrySim.terrain.cells == permanent,
        "Removing an expired object must preserve its crater")
    let meteor = SceneBody(id: 91, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    // Stage a visible flank crossing with the faster massive asteroid; use projected size and speed.
    let bigAge = Double((0.5 + large.apparentRadius + large.entryLeadDistance) / large.screenSpeed)
    let smallAge = Double((0.5 + meteor.apparentRadius + meteor.entryLeadDistance - 0.25) / meteor.screenSpeed)
    let big = SceneBody(id: large.id, birth: 100 - bigAge, seed: 1, depthScale: 1, depthDirection: 0)
    let small = SceneBody(id: meteor.id, birth: 100 - smallAge, seed: 1, depthScale: 1, depthDirection: 0)
    var contactBodies = [big, small]
    resolveBodyCollisions(bodies: &contactBodies, from: 100, to: 101, aspect: aspect)
    precondition(contactBodies[0].collision == nil && contactBodies[0].impactAge == big.impactAge)
    precondition(
        contactBodies[1].collision != nil, "Small meteor must break on the larger body's visible surface")
    let hit = contactBodies[1].collision!
    precondition(hit.point.y > 0 && abs(SceneCamera.project(hit.point).y) < 0.5)
    precondition(contactBodies[1].worldPosition(age: 200, aspect: aspect) == hit.center)
    precondition(contactBodies[1].worldPosition(age: 200, aspect: 16 / 9) == hit.center)
    var reversed = [small, big]
    resolveBodyCollisions(bodies: &reversed, from: 100, to: 101, aspect: aspect)
    precondition(reversed[0].collision != nil && reversed[1].collision == nil)

    var invisible = [
        SceneBody(
            id: big.id, birth: big.birth + Double(3 / big.speed), seed: 1, depthScale: 1, depthDirection: 0),
        SceneBody(
            id: small.id, birth: small.birth + Double(3 / small.speed), seed: 1, depthScale: 1,
            depthDirection: 0),
    ]
    resolveBodyCollisions(bodies: &invisible, from: 100, to: 101, aspect: aspect)
    precondition(invisible.allSatisfy { $0.collision == nil }, "Invisible approach paths must not collide")
    var remnant = big
    remnant.impactEmitted = true
    var remains = [remnant, small]
    resolveBodyCollisions(bodies: &remains, from: 100, to: 101, aspect: aspect)
    precondition(remains[1].collision == nil, "Already broken bodies are not solid bodies")
    var stepped = [big, small]
    for frame in 0..<60 {
        resolveBodyCollisions(
            bodies: &stepped, from: 100 + Double(frame) / 60,
            to: 100 + Double(frame + 1) / 60, aspect: aspect)
    }
    precondition(abs(stepped[1].impactAge - contactBodies[1].impactAge) < 0.0001)

    let collisionSim = SceneSimulation(seed: 1, bodies: [big, small], time: 100)
    var collisionMaterial: [ParticleGPU] = []
    for _ in 0..<120 {
        let frame = collisionSim.advance(delta: 1 / 60, aspect: aspect, palette: 0, births: false)
        collisionMaterial += frame.newParticles.filter { $0.owner.x == Float(small.id) && $0.owner.y == 1 }
        precondition(collisionSim.bodies.first { $0.id == big.id }!.collision == nil)
    }
    precondition(collisionMaterial.count > 500)
    precondition(collisionMaterial.allSatisfy { $0.color.w != 4 }, "Air collisions must not excavate sand")
    precondition(
        collisionMaterial.allSatisfy { $0.position.y > hit.point.y - meteor.worldRadius },
        "Collision debris must remain at its 3D contact")
    precondition(
        collisionMaterial.contains { $0.position.w < 0 } && collisionMaterial.contains { $0.position.w > 0 })
    let broken = collisionSim.bodies.first { $0.id == small.id }!
    let after = collisionSim.advance(delta: 0.1, aspect: aspect, palette: 0, births: false)
    precondition(
        after.newParticles.allSatisfy { $0.owner.x != Float(small.id) },
        "Broken body must stop emitting its trail and burst exactly once")
    precondition(broken.impactEmitted)

    let angled = events.filter { abs($0.slope) > tan(Float.pi / 9) }
    precondition(
        angled.count > 200 && angled.count < 4000, "Pronounced crossing angles must remain occasional")
    precondition(angled.contains { $0.slope < 0 } && angled.contains { $0.slope > 0 })
    precondition(angled.contains { $0.radius >= 0.20 })

    func crossingX(_ body: SceneBody, y: Float) -> Float {
        let age = Double((0.5 + body.apparentRadius + body.entryLeadDistance - y) / body.screenSpeed)
        return body.position(age: age, aspect: 3440 / 1440).x
    }
    let diagonals = Array(angled.prefix(100))
    precondition(
        diagonals.contains { a in
            diagonals.contains { b in
                a.slope * b.slope < 0
                    && (crossingX(a, y: 0.4) - crossingX(b, y: 0.4))
                        * (crossingX(a, y: -0.4) - crossingX(b, y: -0.4)) < 0
            }
        }, "Opposing meteor paths must actually cross inside the screen")

    let sim = SceneSimulation(seed: 1)
    var maxParticles = 0
    var sawLarge = false
    var lastArrival = -1
    var arrivals = 0
    var superheatedArrivals = 0
    var meteorArrivals = 0
    var bolideBirths: [Double] = []
    var showerBirths: [Int: [Double]] = [:]
    var emissionWindow = [Int](repeating: 0, count: 361)
    var recentEmission = 0
    var peakEmission = 0
    for tick in 0..<216000 {
        let frame = sim.advance(delta: 1 / 60, aspect: 3440 / 1440, palette: 0, births: true)
        for body in sim.bodies where body.id > lastArrival {
            arrivals += 1
            if body.model.isBolide { bolideBirths.append(body.birth) }
            if let shower = body.model.showerMember {
                showerBirths[shower.event, default: []].append(body.birth)
            }
            if body.crustFraction <= 0.25 && !body.model.isBolide && body.model.showerMember == nil {
                superheatedArrivals += 1
            }
            if body.crustFraction == 1 && body.model.showerMember == nil { meteorArrivals += 1 }
        }
        lastArrival = max(lastArrival, sim.bodies.map(\.id).max() ?? -1)
        precondition(sim.bodies.filter { $0.radius >= 0.16 }.count <= 1)
        precondition(sim.bodies.count <= 20)
        precondition(sim.bodies.filter(\.model.isBolide).count <= 1)
        precondition(frame.newParticles.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
        precondition(Set(frame.bodies.map { Int($0.color.w) }) == Set(sim.bodies.map(\.id)))
        for (gpuBody, body) in zip(frame.bodies, sim.bodies) {
            precondition(gpuBody.shape.x == body.slope && gpuBody.shape.y == body.crustFraction)
            precondition(gpuBody.spatial.w == body.worldRadius && gpuBody.spatial.z.isFinite)
            precondition(abs(simd_length(SIMD3(gpuBody.flight.x, gpuBody.flight.y, gpuBody.flight.z)) - 1) < 0.00001)
            precondition(
                gpuBody.position.z
                    == body.apparentRadius(
                        at: body.worldPosition(age: sim.time - body.birth, aspect: 3440 / 1440)))
            let burstDepth =
                body.collision?.point.z ?? body.groundContact?.point.z
                ?? body.worldPosition(age: body.impactAge, aspect: 3440 / 1440).z
            precondition(
                gpuBody.motion.x == burstDepth,
                "Burst depth must stay at the resolved contact")
            precondition(
                gpuBody.contact.w == (body.collision == nil ? 1 : 0),
                "Air collisions must not stamp ground craters")
            if let ground = body.groundContact {
                precondition(gpuBody.contact.y == ground.point.y)
            }
        }
        maxParticles = max(maxParticles, frame.newParticles.count)
        let emissionSlot = tick % emissionWindow.count
        recentEmission -= emissionWindow[emissionSlot]
        emissionWindow[emissionSlot] = frame.newParticles.count
        recentEmission += frame.newParticles.count
        peakEmission = max(peakEmission, recentEmission)
        sawLarge = sawLarge || sim.bodies.contains { $0.radius >= 0.16 }
        if tick % 600 == 0 { precondition(sim.bodies.allSatisfy { sim.time < $0.birth + $0.duration }) }
    }
    precondition(sawLarge && maxParticles <= 4096)
    precondition(peakEmission < 32768, "Six seconds of emission must fit the persistent particle ring")
    precondition(
        (70...230).contains(bolideBirths.count),
        "Dramatic events must recur without dominating the entire scene")
    precondition((2...4.1).contains(bolideBirths.first!))
    for (a, b) in zip(bolideBirths, bolideBirths.dropFirst()) {
        precondition((12...25.1).contains(b - a), "Bolides must recur briskly without clustering")
    }
    let showerCount = showerBirths.values.reduce(0) { $0 + $1.count }
    precondition((30...100).contains(showerBirths.count))
    precondition(showerBirths.values.allSatisfy { (8...38).contains($0.count) && $0.last! - $0.first! < 8 })
    precondition(
        (0.12...0.18).contains(
            Double(superheatedArrivals) / Double(arrivals - bolideBirths.count - showerCount)))
    precondition(meteorArrivals > superheatedArrivals)
    print(
        "Arrivals in one simulated hour: \(arrivals), superheated: \(superheatedArrivals), meteors: \(meteorArrivals), shower members: \(showerCount) / \(showerBirths.count) events, peak six-second emission: \(peakEmission)"
    )
    let impact = SceneSimulation(seed: 1, bodies: [large], time: large.groundAge - 0.01)
    var materialCounts: [Int: Int] = [:]
    var impactXs: [Float] = []
    var impactYs: [Float] = []
    for _ in 0..<Int((large.impactAge - large.groundAge + 5) * 60) {
        let frame = impact.advance(delta: 1 / 60, aspect: 3440 / 1440, palette: 0, births: false)
        for p in frame.newParticles where p.owner.y >= 1 && p.owner.y < 2 {
            materialCounts[Int(p.color.w), default: 0] += 1
            impactXs.append(p.position.x)
            impactYs.append(p.position.y)
            precondition(p.position.z.isFinite && p.position.w.isFinite && p.life.z > 0)
        }
    }
    precondition(
        materialCounts[3, default: 0] == 0 && impact.terrain.meltPools.count == 1,
        "A superheated ground strike must become lava without solid body fragments")
    precondition(materialCounts[4, default: 0] >= 70, "Ground contact must eject dust")
    precondition(materialCounts[1, default: 0] >= 300 && materialCounts[2, default: 0] == 0)
    precondition(
        impactXs.max()! - impactXs.min()! > large.worldRadius * 0.2, "Breakup must retain a visible spread")
    precondition(
        impactYs.max()! - impactYs.min()! > 0.1,
        "Ground impact must have a visible vertical spread")
    precondition(MemoryLayout<ParticleGPU>.stride == 96)
    precondition(MemoryLayout<BodyGPU>.stride == 144)
    print(
        "PASS: 10,000 bodies, true 3D contacts/depth, persistent desert impacts, angles, edge coverage, one large body, one simulated hour, bounded emission and GPU layout"
    )
}

/// Tremors use resolved ground contacts and scene age, without changing world physics or pause state.
func runImpactShakeTests() {
    let large = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
    let bolide = SceneBody(id: 80, birth: 0, seed: 1, arrival: .bolide)
    let small = SceneBody(id: 23, birth: 0, seed: 1)
    precondition(large.impactShakeStrength > 0 && bolide.impactShakeStrength > large.impactShakeStrength)
    precondition(small.impactShakeStrength == 0)
    var body = BodyGPU(
        position: .zero, color: SIMD4(1, 0.2, 0.1, 7), motion: .zero,
        cloud: .zero, shape: SIMD4(0, 1, -0.1, 0), contact: SIMD4(0, 0, -5, 1),
        impactEffects: SIMD4(1, 0, 1, 0))
    precondition(SceneCamera.shake(for: [body]) == .zero)
    var peak: Float = 0
    for tick in 0..<120 {
        body.shape.z = Float(tick) / 120
        let shake = SceneCamera.shake(for: [body])
        precondition(shake == SceneCamera.shake(for: [body]), "Paused frames must keep the same displacement")
        precondition(simd_length(SceneCamera.shake(for: Array(repeating: body, count: 20))) <= 0.0041)
        peak = max(peak, simd_length(shake))
        if tick >= 108 { precondition(shake == .zero) }
    }
    precondition(peak > 0.001 && peak <= 0.004)
    body.shape.z = 0.1
    body.contact.w = 0
    precondition(SceneCamera.shake(for: [body]) == .zero, "Air breakups must not shake the ground")
    body.contact.w = 1
    body.impactEffects.z = 0
    precondition(SceneCamera.shake(for: [body]) == .zero)
    print("PASS: ground-only impact tremors, decay, pause, simultaneous bound and exact rest")
}

/// Model identity must determine the impact, independently of the selected trail or crust appearance.
private func runBodyModelTests() {
    let member = MeteorShower.Member(event: 42, slope: 0.6, hue: 0.25)
    let bolide = SceneBody(id: 79, birth: 0, seed: 1, arrival: .bolide)
    let shower = SceneBody(id: 79, birth: 0, seed: 1, arrival: .shower(member))
    guard case .bolide = bolide.model, case .showerMeteor(let stored) = shower.model else {
        preconditionFailure("Explicit arrivals must retain their model identity")
    }
    precondition(stored.event == member.event && stored.slope == member.slope && stored.hue == member.hue)
    precondition(!bolide.makesLavaLake && !shower.makesLavaLake)
    precondition(BodyModel(arrival: .sporadic(), crustFraction: 0.25).groundImpact == .lavaLake)
    precondition(BodyModel(arrival: .sporadic(), crustFraction: 0.25001).groundImpact == .fragments)
    precondition(BodyModel(arrival: .bolide, crustFraction: 0).groundImpact == .fragments)
    for id in 0..<10000 {
        let body = SceneBody(id: id, birth: 0, seed: 13.7)
        switch body.model {
        case .meteor:
            precondition(body.crustFraction > 0.25 && !body.makesLavaLake)
        case .superheatedAsteroid:
            precondition(body.crustFraction <= 0.25 && body.makesLavaLake)
        case .bolide, .showerMeteor:
            preconditionFailure("Sporadic arrivals cannot silently become scheduled events")
        }
    }
    precondition(ParticleKind.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5, 6, 7])
    precondition(ParticleDynamics.allCases.map(\.rawValue) == [-1, 0, 1, 1.5, 2])
    precondition(MemoryLayout<BodyGPU>.stride == 144 && MemoryLayout<ParticleGPU>.stride == 96)
    print("Explicit body models, impact outcomes and particle GPU encodings passed")
}

/// Automatic waves must remain coherent, intermittent and safe to abandon during scene draining.
func runMeteorShowerTests() {
    for seed in [0.0, 1, 17, 99] {
        var schedule = MeteorShower(seed: seed, time: 0)
        var events: [Int: [(Double, MeteorShower.Member)]] = [:]
        for tick in 0..<36000 {
            for arrival in schedule.arrivals(at: Double(tick) / 60, enabled: true, capacity: 20) {
                events[arrival.1.event, default: []].append(arrival)
            }
        }
        let waves = events.keys.sorted().map { events[$0]! }
        precondition((8...12.02).contains(waves.first!.first!.0))
        for wave in waves {
            precondition((17...38).contains(wave.count) && wave.last!.0 - wave.first!.0 < 8)
            precondition(wave.allSatisfy { $0.1.slope == wave[0].1.slope && $0.1.hue == wave[0].1.hue })
            let bodies = wave.enumerated().map {
                SceneBody(id: $0.offset, birth: $0.element.0, seed: seed, arrival: .shower($0.element.1))
            }
            precondition(
                bodies.map(\.hue).max()! - bodies.map(\.hue).min()! > 0.4,
                "Rain must retain broad color variation within a shared theme")
            precondition(
                bodies.allSatisfy {
                    $0.screenSpeed >= 1.55 && $0.screenSpeed <= 2.55 && $0.crustFraction == 1
                })
            precondition(bodies.map(\.depthScale).max()! - bodies.map(\.depthScale).min()! > 1)
            precondition(
                bodies.allSatisfy { abs($0.slope - wave[0].1.slope) <= 0.0251 && $0.entryVelocity.y < 0 })
        }
        for (previous, next) in zip(waves, waves.dropFirst()) {
            precondition((30...57.3).contains(next.first!.0 - previous.first!.0))
        }
    }

    var drain = MeteorShower(seed: 1, time: 0)
    precondition(!drain.arrivals(at: 18, enabled: true, capacity: 20).isEmpty)
    precondition(drain.arrivals(at: 18.5, enabled: false, capacity: 20).isEmpty)
    precondition(drain.arrivals(at: 19, enabled: true, capacity: 20).isEmpty)
    var pressure = MeteorShower(seed: 1, time: 0)
    precondition(pressure.arrivals(at: 18, enabled: true, capacity: 0).isEmpty)
    precondition(
        pressure.arrivals(at: 18, enabled: true, capacity: 20).isEmpty,
        "Capacity pressure must drop arrivals rather than replaying a deferred burst")
    precondition(pressure.arrivals(at: 19, enabled: true, capacity: 1).count == 1)
    print("PASS: meteor shower timing, common radiant, varied depth/speed, drain and capacity pressure")
}

/// Review bundles must not acquire hardware or login permissions even if UI actions request them.
@MainActor func runAmbientIsolationTests() throws {
    runAmbientIdleTests()
    precondition(AmbientScene.allCases.map(\.rawValue) == ["starfall"])
    for saved: String? in [nil, "0", "1", "2", "journey", "starfall", "unknown"] {
        precondition(AmbientScene(savedID: saved) == .meteorFall)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Glowline-ambient-isolation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(stateDirectory: directory, inspectSystem: false, hardwareEnabled: false)
    model.settings.port = directory.path
    model.settings.launchAtLogin = true
    model.begin()
    model.configureLogin()
    model.refreshDevices()
    model.requestPermission()
    model.startEngine()
    model.restartEngine()
    precondition(model.ports.isEmpty && model.displays.isEmpty && !model.permission)
    precondition(!model.isConnected && !model.isStarting)
    precondition(
        model.logURL.path.hasPrefix(directory.path)
            && !FileManager.default.fileExists(atPath: model.logURL.path))
    model.shutdown()
    print("Ambient review isolation: no engine, hardware discovery or permission acquisition")
}

/// Idle launch must never interrupt visible fullscreen work or a manually opened scene.
@MainActor func runAmbientIdleTests() {
    let suite = "Glowline-idle-test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AmbientIdleSettings(defaults: defaults)
    precondition(!settings.enabled && settings.minutes == 5)
    settings.enabled = true
    settings.minutes = 3
    let restored = AmbientIdleSettings(defaults: defaults)
    precondition(restored.enabled && restored.minutes == 3)
    defaults.set(-5, forKey: "idleMinutes")
    precondition(AmbientIdleSettings(defaults: defaults).minutes == 5)

    var policy = AmbientIdlePolicy()
    func step(
        _ idle: Double, enabled: Bool = true, available: Bool = true,
        blocked: Bool = false, open: Bool = false, automatic: Bool = false
    ) -> AmbientIdlePolicy.Action {
        policy.update(
            idleSeconds: idle, delay: 180, enabled: enabled,
            available: available, blocked: blocked, open: open, automatic: automatic)
    }
    precondition(step(179.9) == .none)
    precondition(step(180, blocked: true) == .none)
    precondition(step(300, available: false) == .none)
    precondition(step(300, enabled: false) == .none)
    precondition(step(300, open: true) == .none)
    // A manual session consumes this idle period; closing it must not reopen the scene.
    precondition(step(301) == .none)
    precondition(step(0) == .none)
    precondition(step(180) == .launch)
    precondition(step(181) == .none)
    precondition(step(1, open: true, automatic: true) == .dismiss)
    precondition(step(180) == .launch)
    precondition(step(181, blocked: true, open: true, automatic: true) == .dismiss)
    precondition(step(182) == .none)
    precondition(step(0) == .none)
    precondition(step(180, available: false) == .none)
    precondition(step(180) == .launch)
    precondition(step(181, available: false, open: true, automatic: true) == .dismiss)
    precondition(step(0, enabled: false, available: false, open: true) == .none)
    precondition(step(.nan) == .none && step(.infinity) == .none)

    let displays = [
        CGRect(x: 0, y: 0, width: 3440, height: 1440),
        CGRect(x: -1920, y: -200, width: 1920, height: 1080),
    ]
    precondition(AmbientIdleEnvironment.coversDisplay(displays[0], displays: displays))
    precondition(AmbientIdleEnvironment.coversDisplay(displays[1], displays: displays))
    precondition(
        AmbientIdleEnvironment.coversDisplay(
            CGRect(x: 0, y: 25, width: 3440, height: 1390), displays: displays))
    precondition(
        !AmbientIdleEnvironment.coversDisplay(
            CGRect(x: 0, y: 0, width: 1720, height: 1440), displays: displays))
    precondition(
        !AmbientIdleEnvironment.coversDisplay(
            CGRect(x: 5000, y: 0, width: 3440, height: 1440), displays: displays))
    var window: [String: Any] = [
        kCGWindowOwnerPID as String: NSNumber(value: Int32(42)),
        kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1.0,
        kCGWindowBounds as String: displays[1].dictionaryRepresentation,
    ]
    precondition(AmbientIdleEnvironment.windowBlocksLaunch(window, ownPID: 1, displays: displays))
    precondition(!AmbientIdleEnvironment.windowBlocksLaunch(window, ownPID: 42, displays: displays))
    for layer in [24, 25, -1] {
        window[kCGWindowLayer as String] = layer
        precondition(
            !AmbientIdleEnvironment.windowBlocksLaunch(window, ownPID: 1, displays: displays),
            "Menu/recording overlays must not permanently block launch")
    }
    window[kCGWindowLayer as String] = 3
    precondition(AmbientIdleEnvironment.windowBlocksLaunch(window, ownPID: 1, displays: displays))
    window[kCGWindowAlpha as String] = 0.0
    precondition(!AmbientIdleEnvironment.windowBlocksLaunch(window, ownPID: 1, displays: displays))
    print(
        "PASS: idle preferences, timer boundary, fullscreen displays, one launch per idle, activity/sleep and manual-session isolation"
    )
}

/// Direction changes probabilities and harmonies without a periodic playlist or frame dependence.
func runSceneDirectionTests() {
    var signatures = Set<[Int]>()
    for seed in [0.0, 1, 17, 99] {
        var director = SceneDirector(seed: seed, time: 0)
        var dense = SceneDirector(seed: seed, time: 0)
        var signature: [Int] = []
        var calm = 0
        var active = 0
        for second in 0..<600 {
            let sparse = director.sample(at: Double(second))
            var fine = dense.sample(at: Double(second))
            if second > 0 {
                // A repeated timestamp must not advance the random process.
                fine = dense.sample(at: Double(second))
            }
            precondition(sparse == fine)
            precondition((0...1).contains(sparse.activity))
            if sparse.activity < 0.45 { calm += 1 }
            if sparse.activity > 0.7 { active += 1 }
            signature.append(Int(sparse.activity * 100))
            for id in 0..<20 {
                let composition = sparse.arrival(id: id, seed: seed)
                let delta = abs(composition.hue - sparse.hue)
                let wrapped = min(delta, 1 - delta)
                precondition(
                    wrapped < 0.10 || abs(wrapped - 1 / 3) < 0.05 || abs(wrapped - 0.5) < 0.05,
                    "Arrivals combine related, triadic and complementary hues")
                precondition(sparse.ordinaryDelay(id: id, seed: seed) < 7.2)
                precondition(sparse.bolideDelay(id: id, seed: seed) < 25.1)
            }
        }
        precondition(
            calm > 20 && active > 20, "Every long scene needs both breathing room and strong passages")
        precondition(Array(signature[0..<120]) != Array(signature[120..<240]))
        let snapshot = director.sample(at: 600)
        let hues = (0..<200).map { id -> Float in
            let delta = abs(snapshot.arrival(id: id, seed: seed).hue - snapshot.hue)
            return min(delta, 1 - delta)
        }
        precondition(
            hues.filter { $0 < 0.1 }.count > 50 && hues.filter { $0 > 0.25 && $0 < 0.4 }.count > 35
                && hues.filter { $0 > 0.45 }.count > 20,
            "A theme must keep substantial contrasting color accents")
        let composed = (0..<200).map { id -> SceneBody in
            let composition = snapshot.arrival(id: id, seed: seed)
            let body = SceneBody(id: id, birth: 0, seed: seed, composition: composition)
            precondition(body.hue == composition.hue && body.slope == composition.slope)
            if body.crustFraction <= 0.25 { precondition(body.screenSpeed >= 1.1 - 0.000001) }
            return body
        }
        precondition(composed.contains { $0.slope < 0 } && composed.contains { $0.slope > 0 })
        precondition(Set(composed.map { Int($0.slope * 1000) }).count > 100)
        var relieved = director
        relieved.noteClimax(at: 600, id: 17)
        let after = relieved.sample(at: 600)
        precondition(
            after.activity < snapshot.activity && snapshot.activity - after.activity <= 0.181
                && after.hue == snapshot.hue && after.heading == snapshot.heading)
        var baseline = director
        precondition(
            relieved.sample(at: 604) == baseline.sample(at: 604),
            "Breathing room must recover promptly without forcing a new act")
        signatures.insert(signature)
        var fine = SceneDirector(seed: seed, time: 0)
        for tick in 0...36000 { _ = fine.sample(at: Double(tick) / 60) }
        precondition(
            fine.sample(at: 600) == director.sample(at: 600), "Direction is independent of render cadence")
    }
    precondition(signatures.count == 4, "Different seeds must not replay the same scene")
    print("PASS: irregular direction, quiet/active passages, color harmony, pause and cadence parity")
}
