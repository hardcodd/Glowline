import Foundation

/// Map native slider ticks to units without rewriting stored values on display.
/// A short final interval preserves nonintegral limits such as 33.68 FPS.
struct SliderScale {
    let range: ClosedRange<Double>
    let step: Double
    var lastIndex: Double { ceil((range.upperBound - range.lowerBound) / step - 1e-9) }

    func index(for value: Double) -> Double {
        min(lastIndex, max(0, ((value - range.lowerBound) / step).rounded()))
    }

    func value(at index: Double) -> Double {
        let tick = min(lastIndex, max(0, index.rounded()))
        return min(range.upperBound, range.lowerBound + tick * step)
    }
}
