import Foundation
import simd

@main struct SandContracts {
    static func main() {
        let contacts = (0..<10000).map { index -> SIMD3<Float> in
            let body = SceneBody(id: index, birth: 0, seed: 13.7)
            return body.worldPosition(age: body.groundAge, aspect: 32 / 9)
        }
        print(
            "Contact extent:", contacts.map { $0.x }.min()!, contacts.map { $0.x }.max()!,
            contacts.map { $0.z }.min()!, contacts.map { $0.z }.max()!)
        precondition(
            contacts.allSatisfy { $0.x > -62 && $0.x < 62 && $0.z > -110 && $0.z < 14 },
            "Every sampled impact at the widest supported aspect must fit the persistent terrain")
        let sand = SandTerrain()
        let front = SandTerrain()
        let frontBefore = front.cells
        let frontCenter = SIMD2<Float>(0, -5)
        let frontRadius: Float = 1.5
        let frontTime = 0.75 * sqrt(frontRadius / SandTerrain.gravity)
        front.strike(at: frontCenter, radius: frontRadius, direction: SIMD2(1, 0.3), seed: 7)
        front.advance(delta: Double(frontTime * 0.25))
        var earlyCrest: Float = 0
        for index in front.cells.indices {
            let p = SandTerrain.origin + (SIMD2(Float(index % SandTerrain.resolution),
                Float(index / SandTerrain.resolution)) + 0.5) * SandTerrain.cellSize
            let r = simd_length(p - frontCenter) / frontRadius
            guard r > 0.4, r < 0.75 else { continue }
            earlyCrest = max(earlyCrest, front.cells[index].x - frontBefore[index].x)
        }
        precondition(earlyCrest > 0.008,
            "The excavation crest must travel through the inner annuli before reaching the final rim")
        func crestRadius() -> Float {
            var moment: Float = 0, weight: Float = 0
            for index in front.cells.indices {
                let p = SandTerrain.origin + (SIMD2(Float(index % SandTerrain.resolution),
                    Float(index / SandTerrain.resolution)) + 0.5) * SandTerrain.cellSize
                let r = simd_length(p - frontCenter) / frontRadius
                let raised = front.cells[index].x - frontBefore[index].x
                guard r > 0.35, r < 0.95, raised > 0.008 else { continue }
                moment += r * raised
                weight += raised
            }
            precondition(weight > 0, "A traveling crest must remain visible ahead of the cavity")
            return moment / weight
        }
        let earlyRadius = crestRadius()
        front.advance(delta: Double(frontTime * 0.35))
        precondition(crestRadius() > earlyRadius + 0.12,
            "The raised crest must move outward rather than inflate at a fixed radius")
        front.advance(delta: Double(frontTime * 0.45))
        let finishedFront = front.cells
        front.advance(delta: 1.5)
        var lateRimGrowth: Float = 0
        for index in front.cells.indices {
            let p = SandTerrain.origin + (SIMD2(Float(index % SandTerrain.resolution),
                Float(index / SandTerrain.resolution)) + 0.5) * SandTerrain.cellSize
            let r = simd_length(p - frontCenter) / frontRadius
            guard r > 0.85, r < 1.3 else { continue }
            lateRimGrowth = max(lateRimGrowth, front.cells[index].x - finishedFront[index].x)
        }
        precondition(lateRimGrowth < 0.002,
            "A finished cavity must not acquire a second rising collar from delayed deposits")
        // A simple crater has one continuous wall and crest, followed by a broad
        // exterior shoulder. Moderate incidence must not turn it into a flower.
        let lunar = SandTerrain()
        let lunarCenter = SIMD2<Float>(0, -8)
        lunar.strike(at: lunarCenter, radius: 2, direction: SIMD2(1, 0), seed: 7, obliquity: 0.5)
        lunar.advance(delta: 3)
        func displacement(_ radius: Float, _ angle: Float) -> Float {
            let p = lunarCenter + SIMD2(cos(angle), sin(angle)) * radius
            return lunar.height(at: p) - SandTerrain.regolithHeight(at: p)
        }
        var crestRadii: [Float] = []
        for ray in 0..<24 {
            let angle = Float(ray) * .pi / 12
            let samples = (14...28).map { Float($0) * 0.1 }
            let crest = samples.max { displacement($0, angle) < displacement($1, angle) }!
            crestRadii.append(crest)
            precondition(displacement(2.6, angle) > 0.004,
                "The rim must blend into a broad exterior shoulder instead of a detached narrow ring")
        }
        precondition(crestRadii.max()! - crestRadii.min()! < 0.5,
            "Simple lunar craters remain nearly circular at moderate incidence")
        let point = SIMD2<Float>(0, -8)
        let original = sand.height(at: point)
        let distant = sand.height(at: SIMD2(12, -20))
        let shoulder = point + SIMD2<Float>(0.65, 0)
        let shoulderBefore = sand.height(at: shoulder)
        sand.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7)
        precondition(sand.height(at: shoulder) == shoulderBefore,
            "The excavation front must not cut the outer bowl in the contact frame")
        let punched = sand.height(at: point)
        precondition(punched < original - 0.10, "Impact must punch out a moderate contact core")
        sand.advance(delta: 1 / 60)
        precondition(
            sand.height(at: point) == punched,
            "The excavated floor must not keep stretching downward like a viscous surface")
        precondition(sand.height(at: shoulder) > shoulderBefore - 0.005,
            "The outer bowl waits for the expanding excavation front")
        sand.advance(delta: 0.08 - 1 / 60)
        sand.advance(delta: 0.2)
        precondition(sand.height(at: shoulder) < shoulderBefore - 0.04,
            "The advancing front must expose the outer bowl")
        sand.advance(delta: 1)
        sand.advance(delta: 8)
        let first = sand.height(at: point)
        precondition(first < original - 0.09, "Impact must retain a readable shallow depression")
        precondition(sand.height(at: SIMD2(12, -20)) == distant)
        let snapshot = sand.cells
        for _ in 0..<100 { _ = sand.height(at: point) }
        precondition(sand.cells == snapshot, "Observation and elapsed frames must not erase craters")
        let nextCycle = SceneSimulation(seed: 3, terrain: sand)
        _ = nextCycle.advance(delta: 3, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(nextCycle.terrain.cells == snapshot, "A dark cycle restart must retain the same terrain")
        sand.strike(at: point + SIMD2(0.45, 0), radius: 0.7, direction: SIMD2(0, 1), seed: 13)
        sand.advance(delta: 1)
        precondition(sand.height(at: point) < first, "Overlapping impacts must modify the old bowl")
        for index in 0..<1000 {
            sand.strike(
                at: SIMD2(Float(index % 20) - 10, -Float(index % 17) - 4),
                radius: 0.6, direction: SIMD2(1, 1), seed: Float(index))
            sand.advance(delta: 1)
        }
        precondition(sand.cells.count == SandTerrain.resolution * SandTerrain.resolution)
        precondition(
            sand.cells.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite })
        precondition(sand.cells.allSatisfy { $0.x >= SandTerrain.minimumHeight - 0.0001 && $0.x <= 0.65 },
            "Repeated strikes must never turn a shallow crater into a deep shaft")
        let foreground = SandTerrain()
        for index in 0..<80 {
            foreground.strike(
                at: SIMD2(sin(Float(index) * 2.4) * 1.2, -2 + cos(Float(index) * 1.7) * 0.7),
                radius: 0.6 + Float(index % 5) * 0.22, direction: SIMD2(1, 0.4),
                seed: Float(index), obliquity: 0.6)
            if index % 8 == 0 {
                foreground.launchShock(at: SIMD2(0, -3), bodyRadius: 0.5, direction: SIMD2(1, 0), seed: Float(index))
            }
            foreground.advance(delta: 0.4)
        }
        foreground.advance(delta: 3)
        var highestSightline: Float = -10
        var deepestForeground: Float = 0
        for z in 0..<SandTerrain.resolution {
            for x in 0..<SandTerrain.resolution {
                let p = SandTerrain.origin + (SIMD2(Float(x), Float(z)) + 0.5) * SandTerrain.cellSize
                guard abs(p.x) < 5, p.y < -0.45, p.y > -8 else { continue }
                let height = foreground.cells[z * SandTerrain.resolution + x].x
                highestSightline = max(highestSightline, SceneCamera.project(SIMD3(p.x, height, p.y)).y)
                deepestForeground = min(deepestForeground, height)
            }
        }
        precondition(highestSightline < -0.29, "Repeated foreground impacts must never build walls above the ground horizon")
        precondition(deepestForeground < -0.1 && deepestForeground >= SandTerrain.minimumHeight - 0.0001,
            "Foreground bowls must remain readable without hiding subsequent impacts")
        print("PASS: 80 clustered foreground impacts preserve open sightlines and crater depth")
        let slow = SandTerrain()
        let fast = SandTerrain()
        for field in [slow, fast] { field.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7) }
        slow.advance(delta: 0.08)
        for _ in 0..<8 { fast.advance(delta: 0.01) }
        precondition(
            zip(slow.cells, fast.cells).allSatisfy { abs($0.x - $1.x) < 0.00001 },
            "Excavation timing must not depend on presentation rate")
        let paused = fast.cells
        fast.advance(delta: 0)
        precondition(paused == fast.cells, "Pause must freeze an unfinished crater")
        let continuity = SandTerrain()
        continuity.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7)
        var previous = continuity.height(at: shoulder)
        var movingFrames = 0
        for _ in 0..<30 {
            continuity.advance(delta: 1 / 120)
            let current = continuity.height(at: shoulder)
            if abs(current - previous) > 0.0001 { movingFrames += 1 }
            precondition(abs(current - previous) < 0.035,
                "A local fracture must unfold across ticks rather than pop a whole cell")
            previous = current
        }
        precondition(movingFrames >= 4, "The fracture front must have visible local progression")
        print("PASS: traveling excavation crest, no late collar, local continuity, whole-field cadence and pause")
        let gravity = SandTerrain()
        gravity.strike(at: point, radius: 0.6, direction: SIMD2(1, 0), seed: 7)
        let punchedCells = gravity.cells
        // Measure conservative slumping only after the staggered ejecta have all landed.
        gravity.advance(delta: 1.5)
        let unstable = gravity.cells
        let volume = unstable.reduce(0.0) { $0 + Double($1.x) }
        func steepness(_ field: [SIMD4<Float>]) -> Float {
            var maximum: Float = 0
            for z in 810..<860 {
                for x in 495..<530 {
                    let i = z * SandTerrain.resolution + x
                    maximum = max(
                        maximum, abs(field[i].x - field[i + 1].x),
                        abs(field[i].x - field[i + SandTerrain.resolution].x))
                }
            }
            return maximum / SandTerrain.cellSize
        }
        let punchedSlope = steepness(punchedCells)
        gravity.advance(delta: 8)
        precondition(
            gravity.cells != punchedCells,
            "Dry slope failure and ejecta must alter the freshly punched profile")
        let finalVolume = gravity.cells.reduce(0.0) { $0 + Double($1.x) }
        precondition(abs(finalVolume - volume) < 0.0001, "Slope collapse must conserve displaced volume")
        precondition(
            steepness(gravity.cells) < punchedSlope
                && steepness(gravity.cells) < SandTerrain.reposeSlope + 0.002)
        let resting = gravity.cells
        gravity.advance(delta: 4)
        precondition(gravity.cells == resting, "Stable slopes must rest instead of creeping forever")
        let dry = SandTerrain()
        dry.strike(at: point, radius: 1.1, direction: SIMD2(1, 0.3), seed: 19)
        dry.advance(delta: 1.5)
        let dryRest = dry.cells
        dry.advance(delta: 5)
        precondition(
            dryRest == dry.cells,
            "Dry ejecta slopes must finish their local collapse promptly, without viscous creep")
        let molten = SandTerrain()
        molten.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7, heat: 1)
        molten.advance(delta: 1)
        precondition(molten.meltPools.count == 1 && molten.meltPools[0].location.w == 1)
        let thermalPause = molten.meltPools
        molten.advance(delta: 0)
        precondition(molten.meltPools == thermalPause, "Pause must freeze molten material as well as terrain")
        molten.strike(at: point + SIMD2(0.2, 0), radius: 0.8, direction: SIMD2(1, 1), seed: 8, heat: 0.8)
        precondition(
            molten.meltPools.count == 2, "Overlapping hot impacts must retain independent cooling ages")
        molten.advance(delta: 8)
        precondition(molten.meltPools.isEmpty && molten.height(at: point) < original - 0.08)
        precondition(molten.cells.contains { $0.w > 0.85 }, "Frozen melt must retain a dark fused residue")
        for index in 0..<20 {
            molten.strike(at: point, radius: 0.4, direction: SIMD2(1, 0), seed: Float(index), heat: 1)
        }
        precondition(
            molten.meltPools.count == 16,
            "Thermal source storage must remain bounded during repeated hot impacts")
        let shallowHot = SandTerrain()
        let penetratingHot = SandTerrain()
        shallowHot.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7, heat: 0.75)
        penetratingHot.strike(
            at: point, radius: 1, direction: SIMD2(1, 0), seed: 7, heat: 0.75, penetration: 1)
        for field in [shallowHot, penetratingHot] { field.advance(delta: 1.5) }
        precondition(
            penetratingHot.height(at: point) < shallowHot.height(at: point)
                && penetratingHot.height(at: point) > SandTerrain.minimumHeight,
            "Penetration may vary a shallow bowl without creating a hidden deep pit")
        for _ in 0..<8 {
            shallowHot.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7)
            shallowHot.advance(delta: 2)
        }
        shallowHot.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 7, heat: 1)
        let coreGrid = (point - SandTerrain.origin) / SandTerrain.cellSize
        let coreIndex = Int(coreGrid.y) * SandTerrain.resolution + Int(coreGrid.x)
        precondition(shallowHot.cells[coreIndex].w > 1,
            "An impact at the depth limit must still expose hot material without digging deeper")
        let verticalEjecta = SandTerrain()
        let obliqueEjecta = SandTerrain()
        verticalEjecta.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 23)
        obliqueEjecta.strike(at: point, radius: 1, direction: SIMD2(1, 0), seed: 23, obliquity: 0.9)
        verticalEjecta.advance(delta: 1)
        obliqueEjecta.advance(delta: 1)
        var rayCells = 0
        var forward: Float = 0
        var rearward: Float = 0
        for z in 800..<865 {
            for x in 475..<550 {
                let sample = SandTerrain.origin + (SIMD2(Float(x), Float(z)) + 0.5) * SandTerrain.cellSize
                let offset = sample - point
                let index = z * SandTerrain.resolution + x
                if simd_length(offset) > 1.6 && verticalEjecta.cells[index].w < -0.01 { rayCells += 1 }
                let deposit = max(0, obliqueEjecta.cells[index].x - SandTerrain.regolithHeight(at: sample))
                if simd_length(offset) > 1.5 {
                    if offset.x > 0 { forward += deposit } else { rearward += deposit }
                }
            }
        }
        precondition(rayCells > 30, "Radial ejecta rays must reach well beyond the crater rim")
        precondition(
            forward > rearward * 1.4,
            "An oblique impact must bias the persistent ejecta along incoming travel")
        let massive = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
        let energetic = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0,
            composition: ArrivalComposition(hue: massive.hue, slope: massive.slope, speedScale: 2))
        precondition(energetic.worldRadius == massive.worldRadius
            && energetic.craterRadius > massive.craterRadius * 1.15,
            "For equal bodies a stronger kinetic impact must widen the crater")
        precondition(massive.radius >= 0.16)
        var radialParticles: [ParticleGPU] = []
        ParticleEmitter(seed: 17).emitImpact(
            body: massive, at: SIMD3(0, 0, -5), color: SIMD3(1, 0.3, 0.05),
            palette: 0, terrain: SandTerrain(), into: &radialParticles)
        let grains = radialParticles.filter { $0.color.w == ParticleKind.regolithGrain.rawValue }
        var offsetParticles: [ParticleGPU] = []
        ParticleEmitter(seed: 17).emitImpact(
            body: massive, at: SIMD3(0, 0, -5), color: SIMD3(1, 0.3, 0.05),
            palette: 0, terrain: SandTerrain(), into: &offsetParticles, launchOffset: 0.08)
        for (baseline, offset) in zip(radialParticles, offsetParticles) {
            guard baseline.color.w == ParticleKind.regolithGrain.rawValue
                    || baseline.color.w == ParticleKind.soilDust.rawValue else { continue }
            precondition(abs(offset.life.y - baseline.life.y + 0.08) < 0.00001
                && offset.position == baseline.position && offset.owner == baseline.owner,
                "Subframe contact must delay soil without changing its source or launch velocity")
        }
        let craterRadius = massive.craterRadius
        precondition(grains.allSatisfy { $0.life.x < craterRadius * 0.015 },
                     "Soil fragments must remain small compared with their source crater")
        precondition(grains.allSatisfy { $0.position.y >= 0.005 },
                     "Ejecta must emerge from the struck surface instead of hiding in the excavated bowl")
        precondition(grains.contains { $0.life.y < -0.2 } && grains.contains { $0.life.y >= -0.1 },
                     "Soil must erupt progressively rather than spawning one simultaneous sheet")
        var sectors = Set<Int>()
        for grain in grains {
            let horizontal = SIMD2(grain.position.z, grain.owner.w)
            let source = SIMD2(grain.position.x, grain.owner.z + 5)
            precondition(simd_dot(simd_normalize(source), simd_normalize(horizontal)) > 0.999,
                         "Soil must launch radially without an inherited camera-facing velocity")
            let angle = atan2(horizontal.y, horizontal.x)
            sectors.insert(Int(floor((angle + .pi) / (.pi * 2) * 8)) % 8)
        }
        precondition(sectors.count == 8, "Soil ejecta must spread into every radial sector")
        let ordered = grains.sorted { $0.life.y > $1.life.y }
        let early = ordered.prefix(grains.count / 4), late = ordered.suffix(grains.count / 4)
        func meanSpeed(_ samples: ArraySlice<ParticleGPU>) -> Float {
            samples.reduce(0) { $0 + simd_length(SIMD3($1.position.z, $1.position.w, $1.owner.w)) }
                / Float(samples.count)
        }
        precondition(meanSpeed(early) > meanSpeed(late) * 2,
                     "Excavation must release the fastest material first and slow toward the rim")
        precondition(early.reduce(0) { $0 + $1.life.x } < late.reduce(0) { $0 + $1.life.x },
                     "The later slower curtain must contain coarser material on average")
        let breakup = SceneSimulation(seed: 1, bodies: [massive], time: massive.groundAge - 0.3)
        var chunks = 0
        while breakup.bodies[0].groundContact == nil {
            let frame = breakup.advance(delta: 1 / 120, aspect: 3440 / 1440, palette: 0, births: false)
            chunks += frame.newParticles.filter { $0.color.w == 3 }.count
        }
        precondition(chunks == 0, "Ground impact must convert the body into lava instead of rock fragments")
        precondition(breakup.terrain.meltPools.count == 1, "The contact frame must create the lava lake")
        let impactAge = breakup.bodies[0].groundContact!.age
        let partial = breakup.advance(delta: 0.025, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(
            partial.bodies[0].position.w == 1
                && partial.bodies[0].spatial.y >= breakup.bodies[0].groundContact!.center.y
                    - massive.groundPenetration - 0.00001,
            "The shell must stay opaque and remain within the energy-limited penetration depth")
        let frozenPosition = breakup.bodies[0].worldPosition(age: breakup.time, aspect: 3440 / 1440)
        _ = breakup.advance(delta: 0, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(
            breakup.bodies[0].worldPosition(age: breakup.time, aspect: 3440 / 1440) == frozenPosition)
        let destroyed = breakup.advance(delta: 0.12, aspect: 3440 / 1440, palette: 0, births: false)
        precondition(
            destroyed.bodies[0].position.w == 0, "The parent shell must be gone within the initial impulse")
        precondition(impactAge > 0)
        let slowImpact = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
        let fastImpact = SceneBody(
            id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0, arrival: .bolide)
        precondition(
            fastImpact.groundPenetration / fastImpact.worldRadius
                > slowImpact.groundPenetration / slowImpact.worldRadius * 2,
            "Higher impact energy must penetrate further instead of sharing a fixed sink distance")
        precondition(
            massive.groundPenetration < massive.worldRadius * 0.5 && massive.groundStopTime < 0.2,
            "An ordinary massive strike must arrest sharply, without sinking a whole diameter")
        let showerBody = SceneBody(
            id: 4, birth: 0, seed: 1, arrival: .shower(MeteorShower.Member(event: 1, slope: 0.5, hue: 0.2)))
        precondition(
            massive.makesLavaLake && !fastImpact.makesLavaLake && !showerBody.makesLavaLake,
            "Lava belongs to superheated asteroids, never bolides or meteor-shower members")
        for body in [
            SceneBody(id: 2, birth: 0, seed: 1), massive, fastImpact, showerBody,
            SceneBody(id: 217, birth: 0, seed: 1, depthScale: 1, depthDirection: 0),
        ] {
            let lake = SceneSimulation(seed: 1, bodies: [body], time: body.groundAge - 0.5)
            var soil = 0
            var rocks = 0
            while lake.bodies[0].groundContact == nil {
                let frame = lake.advance(delta: 1 / 120, aspect: 3440 / 1440, palette: 0, births: false)
                soil += frame.newParticles.filter { $0.color.w == 7 }.count
                rocks += frame.newParticles.filter { $0.color.w == 3 }.count
            }
            precondition(soil > 0, "All ground impacts must keep ballistic soil ejecta")
            if body.makesLavaLake {
                precondition(
                    rocks == 0 && lake.terrain.meltPools.count == 1,
                    "Only superheated asteroids melt into lakes instead of emitting rock fragments")
                let pool = lake.terrain.meltPools[0]
                let hit = lake.bodies[0].groundContact!.point
                precondition(
                    pool.shape.w > 0
                        && simd_length(SIMD2(pool.location.x, pool.location.y) - SIMD2(hit.x, hit.z))
                            < 0.0001,
                    "Each lake must belong to its own crater")
            } else {
                precondition(
                    rocks > 0 && lake.terrain.meltPools.isEmpty,
                    "Rocky meteors and bolides must retain fragments without lava")
            }
        }
        for palette in 0...2 {
            let body = SceneBody(id: 217, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
            let scene = SceneSimulation(seed: 1, bodies: [body], time: body.groundAge - 0.5)
            while scene.bodies[0].groundContact == nil {
                _ = scene.advance(delta: 1 / 120, aspect: 3440 / 1440, palette: palette, births: false)
            }
            let inherited = SIMD4(bodyColor(body.hue, palette: palette), Float(1))
            precondition(
                scene.terrain.meltPools[0].color == inherited,
                "Lava must inherit the impacting body's active palette color")
            _ = scene.advance(delta: 0.25, aspect: 3440 / 1440, palette: (palette + 1) % 3, births: false)
            precondition(
                scene.terrain.meltPools[0].color == inherited,
                "Cooling lava must retain its source color when the scene palette changes")
        }
        let pressure = SandTerrain()
        let beforeWave = pressure.cells
        let pressureVolume = beforeWave.reduce(0.0) { $0 + Double($1.x) }
        pressure.launchShock(at: SIMD2(0, -5), bodyRadius: 0.5, direction: SIMD2(1, 0), seed: 27)
        precondition(
            pressure.cells == beforeWave, "Pressure must not alter distant ground before its front arrives")
        pressure.advance(delta: 0.2)
        let pausedWave = pressure.cells
        pressure.advance(delta: 0)
        precondition(pressure.cells == pausedWave, "Pause must freeze pressure and airborne soil deposits")
        let outerPoint = SIMD2<Float>(3.5, -5)
        let outerX = Int((outerPoint.x - SandTerrain.origin.x) / SandTerrain.cellSize)
        let outerZ = Int((outerPoint.y - SandTerrain.origin.y) / SandTerrain.cellSize)
        let outerIndex = outerZ * SandTerrain.resolution + outerX
        precondition(
            pressure.cells[outerIndex] == beforeWave[outerIndex],
            "Ground ahead of the front must remain untouched")
        for _ in 0..<360 { pressure.advance(delta: 1 / 120) }
        let pressureFinalVolume = pressure.cells.reduce(0.0) { $0 + Double($1.x) }
        precondition(
            abs(pressureFinalVolume - pressureVolume) < 0.001,
            "Shock stripping and ballistic deposition must conserve terrain volume")
        precondition(
            pressure.cells != beforeWave && !pressure.takeShockSoil().isEmpty,
            "A pressure front must throw real soil and leave a persistent redistributed surface")
        let pressure30 = SandTerrain()
        let pressure144 = SandTerrain()
        for field in [pressure30, pressure144] {
            field.launchShock(at: SIMD2(0, -5), bodyRadius: 0.5, direction: SIMD2(1, 0), seed: 27)
        }
        for _ in 0..<90 { pressure30.advance(delta: 1 / 30) }
        for _ in 0..<432 { pressure144.advance(delta: 1 / 144) }
        precondition(
            zip(pressure30.cells, pressure144.cells).allSatisfy { abs($0.x - $1.x) < 0.00001 },
            "Pressure-front erosion and deposits must not depend on display cadence")
        pressure.launchShock(at: SIMD2(-500, 500), bodyRadius: 0.5, direction: .zero, seed: 1)
        let crested = SandTerrain()
        crested.strike(at: SIMD2(2, -5), radius: 0.7, direction: SIMD2(1, 0), seed: 17)
        crested.advance(delta: 8)
        func crestHeight() -> Float {
            var height: Float = -2
            for z in 850..<862 {
                for x in 522..<534 { height = max(height, crested.cells[z * SandTerrain.resolution + x].x) }
            }
            return height
        }
        let originalCrest = crestHeight()
        crested.launchShock(at: SIMD2(0, -5), bodyRadius: 0.5, direction: SIMD2(1, 0), seed: 27)
        for _ in 0..<360 { crested.advance(delta: 1 / 120) }
        precondition(
            crestHeight() < originalCrest - 0.01,
            "The passing pressure front must knock down existing crests rather than only paint dust")
        print(
            "PASS: shock-front timing, dry soil redistribution/conservation, crest reduction, pause and 30/144 Hz parity"
        )

        let atLowRate = SandTerrain()
        let atHighRate = SandTerrain()
        for field in [atLowRate, atHighRate] {
            field.strike(at: point, radius: 0.6, direction: SIMD2(1, 0), seed: 7)
        }
        for _ in 0..<60 { atLowRate.advance(delta: 1 / 30) }
        for _ in 0..<288 { atHighRate.advance(delta: 1 / 144) }
        precondition(
            zip(atLowRate.cells, atHighRate.cells).allSatisfy { abs($0.x - $1.x) < 0.00001 },
            "Gravity-driven transport must not depend on display cadence")
        func contact(at fps: Double) -> BodyContact {
            let body = SceneBody(id: 79, birth: 0, seed: 1, depthScale: 1, depthDirection: 0)
            let sample = SceneSimulation(seed: 1, bodies: [body], time: body.groundAge - 0.5)
            while sample.bodies.first?.groundContact == nil {
                _ = sample.advance(delta: 1 / fps, aspect: 3440 / 1440, palette: 0, births: false)
            }
            let landed = sample.bodies[0]
            let hit = landed.groundContact!
            if sample.time - landed.birth - hit.age > 0.00001 {
                precondition(
                    sample.terrain.height(at: SIMD2(hit.point.x, hit.point.z)) < hit.point.y - 0.000001,
                    "The contact frame must already include excavation, without a one-frame delay")
            }
            precondition(
                landed.disintegrationDuration <= 0.09,
                "Ground breakup must finish promptly after the sharp contact attack")
            let sunk = landed.worldPosition(
                age: hit.age + Double(max(landed.disintegrationDuration, landed.groundStopTime)),
                aspect: 3440 / 1440)
            precondition(
                abs(sunk.y - (hit.center.y - landed.groundPenetration)) < 0.00001,
                "Final burial must equal the work-based stopping depth")
            let stopped = landed.worldPosition(
                age: hit.age + Double(landed.groundStopTime) + 1, aspect: 3440 / 1440)
            precondition(sunk == stopped, "Stopped material must not continue creeping into dry ground")
            return hit
        }
        let at30 = contact(at: 30)
        let at144 = contact(at: 144)
        precondition(
            abs(at30.age - at144.age) < 0.00001 && simd_length(at30.point - at144.point) < 0.00001,
            "Terrain contact must not depend on presentation rate")
        print(
            "PASS: permanent excavation, overlapping craters, untouched distance, finite bounded terrain after 1002 impacts"
        )
    }
}
