import Foundation

func runAmbientMotionTests() {
        let events = (0..<10000).map { Star(id: $0, birth: Double($0), seed: 13.7) }
        let giants = events.filter(\.giant)
        precondition(events.contains { $0.meteorFraction == 1 })
        precondition(events.contains { $0.meteorFraction == 0 })
        for star in events {
            precondition((0...1).contains(star.meteorFraction))
            if star.radius >= 0.16 { precondition(star.meteorFraction == 0) }
            if star.radius <= 0.065 { precondition(star.meteorFraction == 1) }
        }
        precondition((15...50).contains(giants.count))
        let sorted = events.sorted { $0.radius < $1.radius }
        for pair in zip(sorted, sorted.dropFirst()) where pair.1.radius - pair.0.radius > 0.000001 {
            precondition(pair.0.speed > pair.1.speed)
            precondition(pair.0.meteorFraction >= pair.1.meteorFraction)
            precondition(pair.0.cue < pair.1.cue)
            precondition(pair.0.cloudLife < pair.1.cloudLife)
        }
        for star in events {
            for aspect: Float in [16/9, 3440/1440, 32/9] {
                let a = star.position(age: star.entryAge, aspect: aspect)
                let b = star.position(age: star.impactAge, aspect: aspect)
                if star.giant {
                    precondition(b.y + star.radius <= -0.16, "Giant upper limb must reach the lower third before breakup")
                    let previousTrigger = Double((1 + star.radius + star.approach) / star.speed)
                    precondition(star.impactAge - previousTrigger > Double(star.radius * 0.6 / star.speed))
                } else { precondition(abs(b.y + 0.5) < 0.0001) }
                precondition(abs(star.slope) <= tan(Float.pi * 34 / 180) + 0.0001)
                if star.radius >= 0.16 { precondition(a.x == b.x) }
                if star.side != 0 {
                    precondition(abs(a.x) + star.radius > aspect / 2)
                    precondition(abs(b.x) + star.radius > aspect / 2)
                } else if !star.giant {
                    precondition(abs(a.x) + star.radius * 0.7 <= aspect / 2 + 0.0001)
                    precondition(abs(b.x) + star.radius * 0.7 <= aspect / 2 + 0.0001)
                }
            }
        }
        // Swept contacts must catch fast meteors between frames and preserve the larger body.
        precondition(sweptContact(from: SIMD2<Float>(0, 2), to: SIMD2<Float>(0, -2), radius: 0.2) != nil)
        precondition(sweptContact(from: SIMD2<Float>(1, 2), to: SIMD2<Float>(1, -2), radius: 0.2) == nil)
        precondition(sweptContact(from: .zero, to: .zero, radius: 0.2) == 0)
        let giant = Star(id: 18, birth: 0, seed: 1)
        let aspect: Float = 3440/1440
        let giantAge = Double((0.5 + giant.radius + giant.approach) / giant.speed)
        let giantX = giant.position(age: giantAge, aspect: aspect).x
        let meteor = (0..<1000).map { Star(id: $0, birth: 0, seed: 1) }.first {
            $0.radius < 0.06 && abs($0.position(age: $0.entryAge, aspect: aspect).x - giantX) < 0.3
        }!
        // Contact the visible upper limb, while the giant center sits below mid-screen.
        let bigY: Float = -0.45
        let smallY = bigY + giant.radius + meteor.radius + 0.05
        let bigAge = Double((0.5 + giant.radius + giant.approach - bigY) / giant.speed)
        let smallAge = Double((0.5 + meteor.radius + meteor.approach - smallY) / meteor.speed)
        let big = Star(id: giant.id, birth: 100 - bigAge, seed: 1)
        let small = Star(id: meteor.id, birth: 100 - smallAge, seed: 1)
        var contactStars = [big, small]
        resolveStarCollisions(stars: &contactStars, from: 100, to: 101, aspect: aspect)
        precondition(contactStars[0].collision == nil && contactStars[0].impactAge == big.impactAge)
        precondition(contactStars[1].collision != nil, "Small meteor must break on the giant's visible surface")
        let hit = contactStars[1].collision!
        precondition(hit.point.y > -0.5 && hit.point.y < 0.5)
        precondition(contactStars[1].position(age: 200, aspect: aspect) == hit.center)
        precondition(contactStars[1].position(age: 200, aspect: 16/9) == hit.center)
        var reversed = [small, big]
        resolveStarCollisions(stars: &reversed, from: 100, to: 101, aspect: aspect)
        precondition(reversed[0].collision != nil && reversed[1].collision == nil)

        var invisible = [Star(id: big.id, birth: big.birth + Double(3 / big.speed), seed: 1),
                         Star(id: small.id, birth: small.birth + Double(3 / small.speed), seed: 1)]
        resolveStarCollisions(stars: &invisible, from: 100, to: 101, aspect: aspect)
        precondition(invisible.allSatisfy { $0.collision == nil }, "Invisible approach paths must not collide")
        var remnant = big
        remnant.exploded = true
        var remains = [remnant, small]
        resolveStarCollisions(stars: &remains, from: 100, to: 101, aspect: aspect)
        precondition(remains[1].collision == nil, "Already broken stars are not solid bodies")
        var stepped = [big, small]
        for frame in 0..<60 {
            resolveStarCollisions(stars: &stepped, from: 100 + Double(frame)/60,
                                  to: 100 + Double(frame+1)/60, aspect: aspect)
        }
        precondition(abs(stepped[1].impactAge - contactStars[1].impactAge) < 0.0001)

        let collisionSim = Universe(seed: 1, stars: [big, small], time: 100)
        var collisionMaterial: [Particle] = []
        for _ in 0..<120 {
            let frame = collisionSim.advance(delta: 1/60, aspect: aspect, palette: 0, births: false)
            collisionMaterial += frame.spawns.filter { $0.owner.x == Float(small.id) && $0.owner.y == 1 }
            precondition(collisionSim.stars.first { $0.id == big.id }!.collision == nil)
        }
        precondition(collisionMaterial.count > 500)
        precondition(collisionMaterial.allSatisfy { $0.position.y > -0.2 }, "Collision debris must not teleport to the floor")
        precondition(collisionMaterial.contains { $0.position.w < 0 } && collisionMaterial.contains { $0.position.w > 0 })
        let broken = collisionSim.stars.first { $0.id == small.id }!
        let after = collisionSim.advance(delta: 0.1, aspect: aspect, palette: 0, births: false)
        precondition(after.spawns.allSatisfy { $0.owner.x != Float(small.id) }, "Broken body must stop emitting its trail and burst exactly once")
        precondition(broken.exploded)

        let angled = events.filter { abs($0.slope) > tan(Float.pi / 9) }
        precondition(angled.count > 200 && angled.count < 2000, "Pronounced crossing angles must remain occasional")
        precondition(angled.contains { $0.slope < 0 } && angled.contains { $0.slope > 0 })
        precondition(angled.allSatisfy { $0.radius < 0.16 && $0.side == 0 })

        func crossingX(_ star: Star, y: Float) -> Float {
            let age = Double((0.5 + star.radius + star.approach - y) / star.speed)
            return star.position(age: age, aspect: 3440/1440).x
        }
        let diagonals = Array(angled.prefix(100))
        precondition(diagonals.contains { a in diagonals.contains { b in
            a.slope * b.slope < 0 && (crossingX(a, y: 0.4) - crossingX(b, y: 0.4))
                * (crossingX(a, y: -0.4) - crossingX(b, y: -0.4)) < 0
        } }, "Opposing meteor paths must actually cross inside the screen")

        let sim = Universe(seed: 1)
        var maxParticles = 0
        var sawGiant = false
        for tick in 0..<216000 {
            let frame = sim.advance(delta: 1/60, aspect: 3440/1440, palette: 0, births: true)
            precondition(sim.stars.filter { $0.radius >= 0.16 }.count <= 1)
            precondition(sim.stars.count <= 20)
            precondition(sim.stars.allSatisfy { !$0.giant || $0.collision == nil })
            precondition(frame.spawns.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
            precondition(Set(frame.suns.map { Int($0.color.w) }) == Set(sim.stars.map(\.id)))
            for (sun, star) in zip(frame.suns, sim.stars) {
                precondition(sun.shape.x == star.slope && sun.shape.y == star.meteorFraction)
            }
            maxParticles = max(maxParticles, frame.spawns.count)
            sawGiant = sawGiant || sim.stars.contains(where: \.giant)
            if tick % 600 == 0 { precondition(sim.stars.allSatisfy { sim.time < $0.birth + $0.duration }) }
        }
        precondition(sawGiant && maxParticles <= 4096)
        let descent = Universe(seed: 1)
        descent.stageGiant(includeDescent: true)
        for _ in 0..<240 {
            let frame = descent.advance(delta: 1/60, aspect: 3440/1440, palette: 0, births: false)
            precondition(frame.spawns.allSatisfy { $0.owner.y == 0 }, "A giant must pass the former trigger without exploding")
        }
        let impact = Universe(seed: 1)
        impact.stageGiant()
        var materialCounts: [Int: Int] = [:]
        var impactXs: [Float] = []
        var impactYs: [Float] = []
        for _ in 0..<300 {
            let frame = impact.advance(delta: 1/60, aspect: 3440/1440, palette: 0, births: false)
            for p in frame.spawns where p.owner.y == 1 {
                materialCounts[Int(p.color.w), default: 0] += 1
                impactXs.append(p.position.x)
                impactYs.append(p.position.y)
                precondition(p.position.z.isFinite && p.position.w.isFinite && p.life.z > 0)
            }
        }
        precondition(materialCounts[3, default: 0] >= 80, "A giant must throw substantial hot fragments")
        precondition(materialCounts[1, default: 0] >= 300 && materialCounts[2, default: 0] >= 150)
        precondition(impactXs.max()! - impactXs.min()! > 0.6, "Giant breakup must retain its broad spread")
        precondition(impactYs.max()! < -0.24, "Initial giant ejecta must originate near the bottom edge")
        precondition(MemoryLayout<Particle>.stride == 64)
        precondition(MemoryLayout<SunGPU>.stride == 80)
        print("PASS: 10,000 stars, size/speed/glow/lifetime, angles, edge coverage, impact, one large star, one simulated hour, bounded emission and GPU layout")
    }

/// Review bundles must not acquire hardware or login permissions even if UI actions request them.
@MainActor func runAmbientIsolationTests() throws {
    precondition(AmbientScene.allCases.map(\.rawValue) == ["starfall"])
    for saved: String? in [nil, "0", "1", "2", "journey", "starfall", "unknown"] {
        precondition(AmbientScene(savedID: saved) == .starfall)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glowline-ambient-isolation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(stateDirectory: directory, inspectSystem: false, hardwareEnabled: false)
    model.settings.port = directory.path
    model.settings.launchAtLogin = true
    model.begin(); model.configureLogin(); model.refreshDevices(); model.requestPermission(); model.startEngine(); model.restartEngine()
    precondition(model.ports.isEmpty && model.displays.isEmpty && !model.permission)
    precondition(!model.isConnected && !model.isStarting)
    precondition(model.logURL.path.hasPrefix(directory.path) && !FileManager.default.fileExists(atPath: model.logURL.path))
    model.shutdown()
    print("Ambient review isolation: no engine, hardware discovery or permission acquisition")
}
