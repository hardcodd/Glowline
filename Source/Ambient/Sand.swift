import Foundation
import simd

/// Three float4s shared with Metal: center x/z, radius, age; flow axis, seed, heat; inherited linear RGB.
/// Active pools expire; fused residue remains in the terrain's scorch channel.
struct MeltPool: Equatable {
    var location: SIMD4<Float>
    var shape: SIMD4<Float>
    var color: SIMD4<Float>
}

/// Shared world-space pressure-front timing; the Metal lens uses the same decelerating radius.
enum ShockPhysics {
    static let duration: Float = 1.6
    static func radius(bodyRadius: Float, age: Float) -> Float {
        max(0.08, bodyRadius) * (0.65 + 10 * max(0, age) / (1 + 0.45 * max(0, age)))
    }
}

/// Representative grains lifted by a pressure front; rendered particles do not own terrain volume.
struct ShockSoilLaunch {
    let point: SIMD3<Float>
    let velocity: SIMD3<Float>
    let seed: Float
}

/// Session-owned terrain. Each float4 stores height, x/z slopes and scorch (>0)/fresh ejecta (<0), matching Metal buffer 2.
/// Impacts edit a fixed 128-unit square; only unfinished excavation and unstable slopes retain work.
final class SandTerrain {
    static let resolution = 1024
    static let cellSize: Float = 0.125
    static let origin = SIMD2<Float>(-64, -112)
    private(set) var cells: [SIMD4<Float>]
    private(set) var revision = 0
    private(set) var impactCount = 0
    private(set) var meltPools: [MeltPool] = []
    private struct Formation {
        var age: Float = 0
        let xs: ClosedRange<Int>
        let zs: ClosedRange<Int>
        /// Cell, thickness, arrival time and fresh-ejecta tint; excavation is already complete.
        let deposits: [(Int, Float, Float, Float)]
    }
    private var formations: [Formation] = []
    private struct ShockParcel {
        let source: Int
        let target: Int
        let lift: Float
        let land: Float
        let attenuation: Float
        let sample: Float
        var amount: Float = 0
    }
    private final class PressureWave {
        var age: Float = 0
        var cursor = 0
        var parcels: [ShockParcel] = []
        var events: [(age: Float, parcel: Int, landing: Bool)] = []
        let xs: ClosedRange<Int>
        let zs: ClosedRange<Int>
        init(xs: ClosedRange<Int>, zs: ClosedRange<Int>) {
            self.xs = xs
            self.zs = zs
        }
    }
    private var pressureWaves: [PressureWave] = []
    private var shockSoil: [ShockSoilLaunch] = []

    func takeShockSoil() -> [ShockSoilLaunch] {
        let launches = shockSoil
        shockSoil.removeAll(keepingCapacity: true)
        return launches
    }

    /// Scene units: grain acceleration matches the GPU; dry regolith rests below 34 degrees.
    static let gravity: Float = 3.2
    static let reposeSlope = tan(Float.pi * 34 / 180)
    private final class Avalanche {
        let xs: ClosedRange<Int>
        let zs: ClosedRange<Int>
        var age: Float
        var changes: [Float]

        init(xs: ClosedRange<Int>, zs: ClosedRange<Int>, age: Float) {
            self.xs = xs
            self.zs = zs
            self.age = age
            changes = [Float](repeating: 0, count: xs.count * zs.count)
        }
    }
    private var avalanches: [Avalanche] = []
    private var remainder: Double = 0
    private var edgeVisits = [UInt32](repeating: 0, count: resolution * resolution * 4)
    private var physicsTick: UInt32 = 0

    init() {
        cells = [SIMD4<Float>](repeating: .zero, count: Self.resolution * Self.resolution)
        for z in 0..<Self.resolution {
            for x in 0..<Self.resolution {
                let p = Self.origin + (SIMD2(Float(x), Float(z)) + 0.5) * Self.cellSize
                cells[z * Self.resolution + x].x = Self.regolithHeight(at: p)
            }
        }
        updateSlopes(x: 0...(Self.resolution - 1), z: 0...(Self.resolution - 1))
    }

    /// Seeded microcraters and low-amplitude relief; shading adds isotropic regolith grain.
    static func regolithHeight(at point: SIMD2<Float>) -> Float {
        let tile = SIMD2(floor(point.x / 3), floor(point.y / 3))
        func sample(_ offset: Float) -> Float {
            let value = sin(tile.x * 127.1 + tile.y * 311.7 + offset) * 43758.5453
            return value - floor(value)
        }
        let seed = sample(0)
        let center = tile * 3 + SIMD2(0.9 + sample(13) * 1.2, 0.9 + sample(29) * 1.2)
        let radius = 0.22 + seed * 0.43
        let distance = simd_length(point - center) / radius
        let bowl = pow(max(0, 1 - distance * distance), 1.5)
        let rim = exp(-pow((distance - 1.05) / 0.19, 2))
        let crater = (-bowl + rim * 0.3) * (0.04 + seed * 0.09)
        return crater + 0.018 * sin(point.x * 1.7 + sin(point.y * 2.3))
            * cos(point.y * 1.31 + sin(point.x * 2.71))
            + 0.009 * sin(point.x * 4.13 + point.y * 3.77)
    }

    func height(at point: SIMD2<Float>) -> Float {
        let grid = (point - Self.origin) / Self.cellSize - 0.5
        guard grid.x >= 0, grid.y >= 0,
            grid.x < Float(Self.resolution - 1), grid.y < Float(Self.resolution - 1)
        else {
            return Self.regolithHeight(at: point)
        }
        let x = Int(grid.x)
        let z = Int(grid.y)
        let u = grid.x - Float(x)
        let v = grid.y - Float(z)
        let a = cells[z * Self.resolution + x].x * (1 - u) + cells[z * Self.resolution + x + 1].x * u
        let b =
            cells[(z + 1) * Self.resolution + x].x * (1 - u) + cells[(z + 1) * Self.resolution + x + 1].x * u
        return a * (1 - v) + b * v
    }

    /// Excavate the current terrain, preserving earlier strikes. An irregular rim deposits displaced sand.
    /// Bounds prevent repeated coincident hits from creating camera-sized spikes or an unbounded pit.
    /// `elapsed` is scene time since swept contact; applying it immediately prevents a one-frame delay.
    /// `heat` (0...1) starts cooling melt; `penetration` (0...1) deepens massive impacts below that melt skin.
    /// `color` is captured at impact so later palette changes cannot recolor existing lakes.
    /// `obliquity` (0...1) biases the footprint and ejecta down the horizontal incoming direction.
    func strike(
        at point: SIMD2<Float>, radius: Float, direction: SIMD2<Float>, seed: Float,
        elapsed: Double = 0, heat: Float = 0, penetration: Float = 0, obliquity: Float = 0,
        color: SIMD3<Float> = SIMD3(1, 0.16, 0.008)
    ) {
        let radius = max(0.38, radius)
        let extent = radius * (4.2 + obliquity * 1.47)
        let low = (point - SIMD2(repeating: extent) - Self.origin) / Self.cellSize
        let high = (point + SIMD2(repeating: extent) - Self.origin) / Self.cellSize
        let x0 = max(0, Int(floor(low.x)))
        let x1 = min(Self.resolution - 1, Int(ceil(high.x)))
        let z0 = max(0, Int(floor(low.y)))
        let z1 = min(Self.resolution - 1, Int(ceil(high.y)))
        guard x0 <= x1, z0 <= z1 else { return }
        let axis = simd_length(direction) > 0.001 ? simd_normalize(direction) : SIMD2(1, 0)
        let across = SIMD2(-axis.y, axis.x)
        let depth = min(1.1, radius * 0.32 * (1 + penetration * 0.8))
        let floorLevel = height(at: point) - depth * (penetration > 0 ? 0.55 : 0.18)
        var deposits: [(Int, Float, Float, Float)] = []
        for z in z0...z1 {
            for x in x0...x1 {
                let p = Self.origin + (SIMD2(Float(x), Float(z)) + 0.5) * Self.cellSize - point
                let q = SIMD2(simd_dot(p, axis) / (1 + obliquity * 0.35), simd_dot(p, across)) / radius
                let angle = atan2(q.y, q.x)
                let irregularity: Float =
                    1 + 0.12 * sin(angle * 3 + seed)
                    + 0.07 * sin(angle * 7 - seed * 1.3) + 0.035 * sin(angle * 13 + seed * 2.1)
                let distance = simd_length(q) / irregularity
                let bowl = pow(max(0, 1 - distance * distance), 1.4)
                // Broken lips and radial ejecta lobes avoid a smooth extruded torus around every strike.
                let lobes =
                    0.65 + 0.22 * sin(angle * 5 + seed * 1.7)
                    + 0.13 * sin(angle * 11 - seed)
                let breaches = 1 - 0.8 * pow(max(0, sin(angle * 3 + seed * 0.7)), 8)
                let rim = exp(-pow((distance - 1.04) / (0.075 + lobes * 0.045), 2)) * lobes * breaches
                let downrange = cos(angle)
                let ray =
                    pow(max(0, sin(angle * 17 + seed + sin(angle * 5 + seed) * 2)), 8)
                    + 0.5 * pow(max(0, sin(angle * 29 - seed * 2)), 12)
                let fan = max(0.08, 1 + obliquity * downrange * 1.3)
                let reach = 3.8 + obliquity * max(0, downrange) * 0.4
                let apron =
                    distance > 1 && distance < reach
                    ? exp(-(distance - 1) * 1.1) * (0.025 + ray * 0.22) * fan : 0
                let index = z * Self.resolution + x
                // A hot floor levels locally before freezing; dry walls keep their excavated profile.
                let excavation =
                    heat > 0
                    ? min(0, max(cells[index].x - depth * bowl, floorLevel) - cells[index].x)
                    : -depth * bowl
                // Contact punches out solid material immediately. Ejecta land in discrete packets.
                cells[index].x = clamp(cells[index].x + excavation, -2, 0.65)
                if bowl > 0.001 { cells[index].w = max(cells[index].w, bowl * (heat > 0 ? 1.2 : 0.8)) }
                let deposit = depth * (0.55 * rim * max(0.2, 1 + obliquity * downrange * 0.7) + apron)
                if deposit > 0.00001 {
                    let jitter = Float(hash(Double(index) * 0.73 + Double(seed)))
                    let fresh = distance > 1 && deposit > 0.001 ? min(1, deposit * 18) : 0
                    deposits.append(
                        (index, deposit, min(0.29, 0.045 + jitter * 0.055 + distance * 0.05), fresh))
                }
            }
        }
        var formation = Formation(
            xs: max(0, x0 - 1)...min(Self.resolution - 1, x1 + 1),
            zs: max(0, z0 - 1)...min(Self.resolution - 1, z1 + 1), deposits: deposits)
        apply(&formation, delta: elapsed)
        updateSlopes(x: formation.xs, z: formation.zs)
        if formation.age < 0.3 { formations.append(formation) }
        activateSlopes(x: formation.xs, z: formation.zs, age: formation.age)
        if heat > 0 {
            if meltPools.count == 16 { meltPools.removeFirst() }
            meltPools.append(
                MeltPool(
                    location: SIMD4(point.x, point.y, radius * 0.98, Float(elapsed)),
                    shape: SIMD4(axis.x, axis.y, seed, clamp(heat, 0, 1)),
                    color: SIMD4(color, 1)))
        }
        impactCount += 1
        revision += 1
    }

    /// Schedule one dry surface impulse as the spherical front crosses each cell. Removed volume
    /// stays in a parcel until ballistic landing; no continuous height interpolation or liquid flow.
    func launchShock(
        at center: SIMD2<Float>, bodyRadius: Float, direction: SIMD2<Float>,
        seed: Float, elapsed: Double = 0
    ) {
        let reach = ShockPhysics.radius(bodyRadius: bodyRadius, age: ShockPhysics.duration)
        let low = (center - SIMD2(repeating: reach + bodyRadius) - Self.origin) / Self.cellSize
        let high = (center + SIMD2(repeating: reach + bodyRadius) - Self.origin) / Self.cellSize
        guard low.x < Float(Self.resolution - 2), low.y < Float(Self.resolution - 2),
            high.x > 1, high.y > 1
        else { return }
        let xs = max(1, Int(floor(low.x)))...min(Self.resolution - 2, Int(ceil(high.x)))
        let zs = max(1, Int(floor(low.y)))...min(Self.resolution - 2, Int(ceil(high.y)))
        let wave = PressureWave(xs: xs, zs: zs)
        let axis = simd_length(direction) > 0.001 ? simd_normalize(direction) : SIMD2(1, 0)
        for z in zs {
            for x in xs {
                let point = Self.origin + (SIMD2(Float(x), Float(z)) + 0.5) * Self.cellSize
                let offset = point - center
                let distance = simd_length(offset)
                guard distance > bodyRadius * 2.8, distance < reach else { continue }
                let radial = offset / distance
                let normalized = distance / max(0.08, bodyRadius) - 0.65
                let lift = normalized / (10 - 0.45 * normalized)
                let sample = Float(hash(Double(z * Self.resolution + x) + Double(seed) * 73.7))
                let flight = 0.22 + sample * 0.24
                let destination = point + (radial + axis * 0.15) * bodyRadius * (0.45 + sample * 0.6)
                let grid = (destination - Self.origin) / Self.cellSize
                let tx = clamp(Int(grid.x), 1, Self.resolution - 2)
                let tz = clamp(Int(grid.y), 1, Self.resolution - 2)
                let fade = clamp((ShockPhysics.duration - lift) / 0.8, 0, 1)
                let attenuation =
                    exp(-distance / max(0.08, bodyRadius * 7)) * fade
                    * (0.85 + max(-0.5, simd_dot(radial, axis)) * 0.3)
                let index = wave.parcels.count
                wave.parcels.append(
                    ShockParcel(
                        source: z * Self.resolution + x, target: tz * Self.resolution + tx,
                        lift: lift, land: lift + flight, attenuation: attenuation, sample: sample))
                wave.events.append((lift, index, false))
                wave.events.append((lift + flight, index, true))
            }
        }
        wave.events.sort { $0.age == $1.age ? $0.parcel < $1.parcel : $0.age < $1.age }
        let changed = advanceShock(wave, delta: Float(max(0, elapsed)))
        if wave.cursor < wave.events.count { pressureWaves.append(wave) }
        if changed {
            updateSlopes(x: xs, z: zs)
            revision += 1
        }
    }

    /// Chronological lift/landing events conserve soil, including at terrain height limits.
    private func advanceShock(_ wave: PressureWave, delta: Float) -> Bool {
        wave.age += delta
        var changed = false
        while wave.cursor < wave.events.count && wave.events[wave.cursor].age <= wave.age {
            let event = wave.events[wave.cursor]
            let parcel = wave.parcels[event.parcel]
            if event.landing {
                let deposited = min(parcel.amount, max(0, 0.65 - cells[parcel.target].x))
                cells[parcel.target].x += deposited
                cells[parcel.source].x += parcel.amount - deposited
                if deposited > 0 {
                    cells[parcel.target].w = min(cells[parcel.target].w, -min(1, deposited * 25))
                }
            } else {
                let index = parcel.source
                let mean =
                    (cells[index - 1].x + cells[index + 1].x
                        + cells[index - Self.resolution].x + cells[index + Self.resolution].x) * 0.25
                let ridge = max(0, cells[index].x - mean)
                let amount = min(
                    max(0, cells[index].x + 2), min(0.06, (0.004 + ridge * 0.7) * parcel.attenuation))
                wave.parcels[event.parcel].amount = amount
                cells[index].x -= amount
                if amount > 0.0001 && parcel.sample < 0.1 {
                    let source =
                        Self.origin
                        + (SIMD2(Float(index % Self.resolution), Float(index / Self.resolution)) + 0.5)
                        * Self.cellSize
                    let target =
                        Self.origin
                        + (SIMD2(
                            Float(parcel.target % Self.resolution), Float(parcel.target / Self.resolution))
                            + 0.5) * Self.cellSize
                    let flight = parcel.land - parcel.lift
                    let velocity = (target - source) / flight
                    shockSoil.append(
                        ShockSoilLaunch(
                            point: SIMD3(source.x, cells[index].x + 0.02, source.y),
                            velocity: SIMD3(velocity.x, Self.gravity * flight * 0.5, velocity.y),
                            seed: parcel.sample * 1000))
                }
            }
            changed = changed || parcel.amount > 0 || !event.landing
            wave.cursor += 1
        }
        return changed
    }

    /// Ballistic rim packets finish by 0.3 seconds; dry slope failures move without deforming the floor.
    /// A zero delta freezes both phases. Fixed physics ticks preserve cadence-independent transport.
    func advance(delta: Double) {
        guard delta > 0 else { return }
        for index in meltPools.indices { meltPools[index].location.w += Float(delta) }
        meltPools.removeAll { $0.location.w >= 8 }
        guard !formations.isEmpty || !avalanches.isEmpty || !pressureWaves.isEmpty else { return }
        remainder += delta
        let step = 1.0 / 120
        let dirtyRegions = avalanches
        let dirtyWaves = pressureWaves
        var changed = false
        while remainder + 1e-10 >= step {
            remainder -= step
            physicsTick &+= 1
            if physicsTick == 0 {
                edgeVisits = [UInt32](repeating: 0, count: edgeVisits.count)
                physicsTick = 1
            }
            for wave in pressureWaves {
                let moved = advanceShock(wave, delta: Float(step))
                changed = changed || moved
                if wave.cursor == wave.events.count { activateSlopes(x: wave.xs, z: wave.zs, age: 0.3) }
            }
            pressureWaves.removeAll { $0.cursor == $0.events.count }
            for i in formations.indices { apply(&formations[i], delta: step) }
            changed = changed || !formations.isEmpty
            formations.removeAll { $0.age >= 0.3 }
            for i in avalanches.indices.reversed() {
                avalanches[i].age += Float(step)
                // Excavation is impulsive; gravity then collapses the freshly exposed lips and walls.
                guard avalanches[i].age >= 0.08 else { continue }
                let moving = settle(avalanches[i], delta: Float(step))
                changed = changed || moving
                if !moving && avalanches[i].age >= 0.3 { avalanches.remove(at: i) }
            }
            if formations.isEmpty && avalanches.isEmpty && pressureWaves.isEmpty {
                remainder = 0
                break
            }
        }
        if changed {
            // Transport reads heights only. Rebuild display/contact normals once after all physics ticks.
            for patch in dirtyRegions {
                updateSlopes(
                    x: max(0, patch.xs.lowerBound - 1)...min(Self.resolution - 1, patch.xs.upperBound + 1),
                    z: max(0, patch.zs.lowerBound - 1)...min(Self.resolution - 1, patch.zs.upperBound + 1))
            }
            for wave in dirtyWaves {
                updateSlopes(
                    x: max(0, wave.xs.lowerBound - 4)...min(Self.resolution - 1, wave.xs.upperBound + 4),
                    z: max(0, wave.zs.lowerBound - 4)...min(Self.resolution - 1, wave.zs.upperBound + 4))
            }
            revision += 1
        }
    }

    /// Keep work local to each strike; generation stamps deduplicate their shared edges.
    /// Merging bounding rectangles would accumulate large stable gaps during a long session.
    private func activateSlopes(x: ClosedRange<Int>, z: ClosedRange<Int>, age: Float) {
        let patch = Avalanche(
            xs: max(0, x.lowerBound - 3)...min(Self.resolution - 1, x.upperBound + 3),
            zs: max(0, z.lowerBound - 3)...min(Self.resolution - 1, z.upperBound + 3), age: age)
        avalanches.append(patch)
    }

    /// Conservative finite-volume transport: each edge removes exactly what its lower cell receives.
    /// Gravity sets travel speed; static friction halts transport at the repose slope. Region-local
    /// Jacobi deltas reduce scan bias, and eighth-edge limits prevent eight-neighbor overshoot.
    private func settle(_ patch: Avalanche, delta: Float) -> Bool {
        let width = patch.xs.count
        let count = width * patch.zs.count
        for index in 0..<count { patch.changes[index] = 0 }
        let threshold = Self.cellSize * Self.reposeSlope
        let movingThreshold = Self.cellSize * tan(Float.pi * 31 / 180)
        var moved = false
        for z in patch.zs {
            for x in patch.xs {
                let a = z * Self.resolution + x
                let local = (z - patch.zs.lowerBound) * width + x - patch.xs.lowerBound
                // Static friction holds a dry slope until failure; dynamic friction allows a short avalanche.
                // Direct edge calls avoid allocating an array for every terrain cell and physics tick.
                func transfer(to b: Int, target: Int, spacing: Float, edge: Int) {
                    let identity = a * 4 + edge
                    if edgeVisits[identity] == physicsTick { return }
                    edgeVisits[identity] = physicsTick
                    let difference = cells[a].x - cells[b].x
                    if abs(difference) - threshold * spacing <= 0.0001 { return }
                    let excess = abs(difference) - movingThreshold * spacing
                    let amount = min(excess * 0.125, sqrt(2 * Self.gravity * excess) * delta * 3.2 / spacing)
                    let transfer = difference > 0 ? amount : -amount
                    patch.changes[local] -= transfer
                    patch.changes[target] += transfer
                    moved = true
                }
                if x < patch.xs.upperBound { transfer(to: a + 1, target: local + 1, spacing: 1, edge: 0) }
                if z < patch.zs.upperBound {
                    transfer(to: a + Self.resolution, target: local + width, spacing: 1, edge: 1)
                    if x < patch.xs.upperBound {
                        transfer(
                            to: a + Self.resolution + 1, target: local + width + 1, spacing: 1.41421356,
                            edge: 2)
                    }
                    if x > patch.xs.lowerBound {
                        transfer(
                            to: a + Self.resolution - 1, target: local + width - 1, spacing: 1.41421356,
                            edge: 3)
                    }
                }
            }
        }
        if moved {
            for z in patch.zs {
                for x in patch.xs {
                    cells[z * Self.resolution + x].x +=
                        patch.changes[(z - patch.zs.lowerBound) * width + x - patch.xs.lowerBound]
                }
            }
        }
        return moved
    }

    /// A cell receives its ejecta once at arrival, without a continuous surface-height tween.
    private func apply(_ formation: inout Formation, delta: Double) {
        let old = formation.age
        formation.age += Float(max(0, delta))
        for (index, thickness, arrival, fresh) in formation.deposits
        where old < arrival && formation.age >= arrival {
            cells[index].x = clamp(cells[index].x + thickness, -2, 0.65)
            if fresh > 0 { cells[index].w = min(cells[index].w, -fresh) }
        }
    }

    private func updateSlopes(x xs: ClosedRange<Int>, z zs: ClosedRange<Int>) {
        let size = Self.resolution
        for z in zs {
            for x in xs {
                cells[z * size + x].y =
                    (cells[z * size + min(size - 1, x + 1)].x
                        - cells[z * size + max(0, x - 1)].x) / (2 * Self.cellSize)
                cells[z * size + x].z =
                    (cells[min(size - 1, z + 1) * size + x].x
                        - cells[max(0, z - 1) * size + x].x) / (2 * Self.cellSize)
            }
        }
    }
}
