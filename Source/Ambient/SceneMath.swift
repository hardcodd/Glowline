import Foundation
import simd

func hash(_ value: Double) -> Double {
    let n = sin(value * 127.1 + 311.7) * 43758.5453
    return n - floor(n)
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T { min(high, max(low, value)) }

func bodyColor(_ hue: Float, palette: Int) -> SIMD3<Float> {
    let h =
        palette == 1
        ? 0.48 + (hue - floor(hue)) * 0.32 : palette == 2 ? 0.92 + (hue - floor(hue)) * 0.22 : hue
    let k = SIMD3<Float>(0, 2 / 3, 1 / 3)
    let p = abs(simd_fract(SIMD3(repeating: h) + k) * 6 - SIMD3(repeating: 3))
    let rgb = simd_clamp(p - SIMD3(repeating: 1), SIMD3(repeating: 0), SIMD3(repeating: 1))
    return SIMD3(repeating: 0.025) + rgb * 0.975
}
