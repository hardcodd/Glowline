import Foundation

@main struct SliderStepTests {
    static func main() {
        func close(_ a: Double, _ b: Double) { precondition(abs(a-b) < 1e-10, "\(a) != \(b)") }
        for (range, step) in [(0.0...1.0,0.01), (0.0...0.9,0.01), (0.0...2.0,0.01), (0.0...0.2,0.01), (0.0...0.35,0.01), (0.5...2.5,0.01), (0.0...1.0,0.001), (0.05...1.0,0.001), (0.1...5.0,0.1), (5.0...33.68,1.0)] {
            let scale = SliderScale(range: range, step: step)
            close(scale.value(at: 0), range.lowerBound)
            close(scale.value(at: scale.lastIndex), range.upperBound)
            for index in 0...Int(scale.lastIndex) {
                let value = scale.value(at: Double(index))
                precondition(range.contains(value))
                close(scale.index(for: value), Double(index))
                if index > 0 { precondition(value > scale.value(at: Double(index-1))) }
            }
            close(scale.value(at: -100), range.lowerBound)
            close(scale.value(at: scale.lastIndex+100), range.upperBound)
        }
        let percent = SliderScale(range: 0...2, step: 0.01)
        close(percent.value(at: percent.index(for: 0.601484375)+1), 0.61)
        close(percent.value(at: 63.26), 0.63)
        let fps = SliderScale(range: 5...33.68, step: 1)
        close(fps.value(at: fps.lastIndex-1),33)
        close(fps.value(at: fps.lastIndex),33.68)
        print("Whole percentage, time, gamma, speed and bounded FPS slider contracts passed")
    }
}
