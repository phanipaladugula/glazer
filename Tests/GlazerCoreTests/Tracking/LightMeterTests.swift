import Testing

@testable import GlazerCore

@Suite("LightMeter")
struct LightMeterTests {
    @Test("A well-lit frame is good")
    func good() {
        var meter = LightMeter()
        #expect(meter.update(brightness: 0.4) == .good)
    }

    @Test("A dark room drops to too dark")
    func tooDark() {
        var meter = LightMeter()
        #expect(meter.update(brightness: 0.02) == .tooDark)
    }

    @Test("Levels change gradually, not on a single frame")
    func averaged() {
        var meter = LightMeter()
        meter.update(brightness: 0.4)
        #expect(meter.update(brightness: 0.0) == .good)
    }

    @Test("Moving back up needs a little more light than moving down")
    func hysteresis() {
        var meter = LightMeter(smoothing: 1)
        #expect(meter.update(brightness: 0.14) == .dim)
        #expect(meter.update(brightness: 0.155) == .dim)
        #expect(meter.update(brightness: 0.18) == .good)
    }
}

@Suite("LightMeter, every transition")
struct LightMeterTransitionTests {
    @Test("Dim drops to too dark when it gets darker still")
    func dimToTooDark() {
        var meter = LightMeter(smoothing: 1)
        #expect(meter.update(brightness: 0.1) == .dim)
        #expect(meter.update(brightness: 0.02) == .tooDark)
    }

    @Test("Too dark recovers to dim, then to good, each with a little headroom")
    func recovery() {
        var meter = LightMeter(smoothing: 1)
        #expect(meter.update(brightness: 0.02) == .tooDark)
        #expect(meter.update(brightness: 0.07) == .tooDark)
        #expect(meter.update(brightness: 0.09) == .dim)
        #expect(meter.update(brightness: 0.4) == .good)
    }

    @Test("Too dark can recover straight to good")
    func straightToGood() {
        var meter = LightMeter(smoothing: 1)
        meter.update(brightness: 0.01)
        #expect(meter.update(brightness: 0.5) == .good)
    }
}
