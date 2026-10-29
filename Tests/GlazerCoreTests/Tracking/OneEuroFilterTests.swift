import Testing

@testable import GlazerCore

@Suite("OneEuroFilter")
struct OneEuroFilterTests {
    @Test("The first sample passes through unchanged")
    func firstSample() {
        var filter = OneEuroFilter()
        #expect(filter.filter(12, at: 0) == 12)
    }

    @Test("A constant signal stays constant")
    func constant() {
        var filter = OneEuroFilter()
        for step in 0..<20 {
            #expect(abs(filter.filter(5, at: Double(step) * 0.1) - 5) < 1e-9)
        }
    }

    @Test("Jitter around a value is reduced")
    func reducesJitter() {
        var filter = OneEuroFilter()
        var largest = 0.0
        for step in 0..<40 {
            let noisy = step.isMultiple(of: 2) ? 2.0 : -2.0
            let smoothed = filter.filter(noisy, at: Double(step) * 0.1)
            if step > 10 { largest = max(largest, abs(smoothed)) }
        }
        #expect(largest < 1.5)
    }

    @Test("A sustained turn is followed")
    func followsTurn() {
        var filter = OneEuroFilter()
        _ = filter.filter(0, at: 0)
        var value = 0.0
        for step in 1...15 {
            value = filter.filter(30, at: Double(step) * 0.1)
        }
        #expect(value > 28)
    }

    @Test("After a reset, the next sample is taken as is")
    func reset() {
        var filter = OneEuroFilter()
        _ = filter.filter(0, at: 0)
        filter.reset()
        #expect(filter.filter(40, at: 0.1) == 40)
    }
}
