import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("Grab detector")
struct GrabDetectorTests {
    /// A detector fed one frame every 1/12 s, as the camera delivers them.
    struct Run {
        var detector = GrabDetector(calibration: Hands.calibration)
        var time = 0.0
        var events: [GrabDetector.Event] = []

        mutating func show(_ bend: Double?, for duration: Double, x: Double = 0.5, confidence: Double = 0.9) {
            let end = time + duration
            while time < end {
                if let event = detector.update(bend.map { hand(bend: $0, x: x, confidence: confidence) }, at: time) {
                    events.append(event)
                }
                time += 1.0 / 12
            }
        }

        /// Open, then close and hold: a grab.
        mutating func grab() {
            show(Hands.open, for: 0.5)
            show(Hands.fist, for: 0.6)
        }
    }

    @Test("Open then closed is a grab, dated from the open hand")
    func grab() throws {
        var run = Run()
        run.grab()

        let event = try #require(run.events.first)
        guard case .grabbed(let startedAt) = event else {
            Issue.record("Expected a grab, got \(event)")
            return
        }
        #expect(startedAt > 0.3 && startedAt < 0.6)
        #expect(run.events.count == 1)
        #expect(run.detector.phase == .holding)
    }

    @Test("Opening after a grab is a drop")
    func drop() {
        var run = Run()
        run.grab()
        run.show(Hands.fist, for: 2)
        run.show(Hands.open, for: 0.6)

        #expect(run.events.count == 2)
        guard case .dropped(let startedAt) = run.events.last else {
            Issue.record("Expected a drop, got \(run.events)")
            return
        }
        // The fist opened at 3.1 s; smoothing recognises it a frame or two later.
        #expect(startedAt > 3.0 && startedAt < 3.4)
        #expect(run.detector.phase == .idle)
    }

    @Test("A fist with no open hand before it is ignored, like a hand holding a mug")
    func staticFist() {
        var run = Run()
        run.show(Hands.fist, for: 3)

        #expect(run.events.isEmpty)
    }

    @Test("Closing too long after the hand was open is ignored")
    func tooSlow() {
        var run = Run()
        run.show(Hands.open, for: 0.5)
        run.show(Hands.halfway, for: 1.5)
        run.show(Hands.fist, for: 1)

        #expect(run.events.isEmpty)
    }

    @Test("A hand that closes while moving is ignored, like one reaching for something")
    func moving() {
        var run = Run()
        run.show(Hands.open, for: 0.5, x: 0.2)
        run.show(Hands.fist, for: 1, x: 0.6)

        #expect(run.events.isEmpty)
    }

    @Test("A fist too brief to hold is ignored")
    func briefFist() {
        var run = Run()
        run.show(Hands.open, for: 0.5)
        run.show(Hands.fist, for: 0.1)
        run.show(Hands.open, for: 1)

        #expect(run.events.isEmpty)
    }

    @Test("One misread frame doesn't break a fist")
    func misreadFrame() {
        var run = Run()
        run.show(Hands.open, for: 0.5)
        run.show(Hands.fist, for: 0.17)
        run.show(Hands.open, for: 0.05)
        run.show(Hands.fist, for: 0.5)

        #expect(run.events.count == 1)
    }

    @Test("Unsure hands don't count")
    func lowConfidence() {
        var run = Run()
        run.show(Hands.open, for: 0.5, confidence: 0.2)
        run.show(Hands.fist, for: 1, confidence: 0.2)

        #expect(run.events.isEmpty)
        #expect(run.detector.openness == nil)
    }

    @Test("A grab held too long is cancelled")
    func holdLimit() {
        var run = Run()
        run.grab()
        run.show(Hands.fist, for: 16)

        #expect(run.events.last == .cancelled)
        #expect(run.detector.phase == .idle)
    }

    @Test("A grab is cancelled when the hand stays out of view")
    func handGone() {
        var run = Run()
        run.grab()
        run.show(nil, for: 7)

        #expect(run.events.last == .cancelled)
    }

    @Test("A held fist drops as soon as it clearly opens, before the fingers spread fully")
    func quickDrop() {
        var run = Run()
        run.grab()
        let opened = run.time
        // Two thirds open: a fist opening, not yet a spread hand.
        run.show(0.45, for: 0.4)

        guard case .dropped(let startedAt) = run.events.last else {
            Issue.record("Expected a drop, got \(run.events)")
            return
        }
        #expect(startedAt - opened < 0.1)
    }

    @Test("One misread open frame doesn't drop a held fist")
    func heldMisread() {
        var run = Run()
        run.grab()
        run.show(Hands.open, for: 0.05)
        run.show(Hands.fist, for: 1)

        #expect(run.events.count == 1)
        #expect(run.detector.phase == .holding)
    }

    @Test("A hand lowered briefly while held can still drop")
    func lowered() {
        var run = Run()
        run.grab()
        run.show(nil, for: 2)
        run.show(Hands.open, for: 0.5)

        guard case .dropped = run.events.last else {
            Issue.record("Expected a drop, got \(run.events)")
            return
        }
    }

    @Test("No grab can start right after a drop")
    func cooldown() {
        var run = Run()
        run.grab()
        run.show(Hands.open, for: 0.3)
        // Straight back into a fist, within the cooldown.
        run.show(Hands.fist, for: 0.5)

        #expect(run.events.count == 2)

        run.show(Hands.open, for: 1.5)
        run.show(Hands.fist, for: 0.6)
        #expect(run.events.count == 3)
    }

    @Test("A grab adopted from a linked Mac drops when the hand opens here")
    func adopted() {
        var run = Run()
        run.detector.adoptHold(at: 0)
        #expect(run.detector.phase == .holding)

        run.show(Hands.fist, for: 0.5)
        run.show(Hands.open, for: 0.5)
        guard case .dropped = run.events.last else {
            Issue.record("Expected a drop, got \(run.events)")
            return
        }
    }

    @Test("Adopting while already holding changes nothing")
    func adoptWhileHolding() {
        var run = Run()
        run.grab()
        run.detector.adoptHold(at: 10)
        run.show(Hands.fist, for: 15)

        #expect(run.events.last == .cancelled)
    }

    @Test("Reset gives up a grab")
    func reset() {
        var run = Run()
        run.grab()
        run.detector.reset()

        #expect(run.detector.phase == .idle)
        #expect(run.detector.openness == nil)
    }

    @Test("Openness is reported while a hand is in view")
    func openness() throws {
        var run = Run()
        run.show(Hands.open, for: 0.3)
        #expect(try #require(run.detector.openness) > 0.9)

        run.show(nil, for: 0.1)
        #expect(run.detector.openness == nil)
    }
}

@Suite("Display history")
struct DisplayHistoryTests {
    @Test("It returns the display faced at a moment")
    func lookUp() {
        var history = DisplayHistory()
        history.record(1, at: 0)
        history.record(2, at: 1)

        #expect(history.display(at: 0.5) == 1)
        #expect(history.display(at: 1) == 2)
        #expect(history.display(at: 9) == 2)
    }

    @Test("Moments with no face keep the last display")
    func noFace() {
        var history = DisplayHistory()
        history.record(1, at: 0)
        history.record(nil, at: 1)

        #expect(history.display(at: 1.5) == 1)
    }

    @Test("Before anything was recorded, the earliest display is used")
    func before() {
        var history = DisplayHistory()
        history.record(3, at: 2)

        #expect(history.display(at: 1) == 3)
        #expect(DisplayHistory().display(at: 0) == nil)
    }

    @Test("A display can be required near a moment")
    func near() {
        var history = DisplayHistory()
        history.record(1, at: 0)
        history.record(2, at: 2)

        #expect(history.display(near: 0.3, within: 0.5) == 1)
        #expect(history.display(near: 1.9, within: 0.5) == 2)
        #expect(history.display(near: 1, within: 0.5) == nil)
    }

    @Test("Old entries are forgotten")
    func forgets() {
        var history = DisplayHistory(span: 2)
        history.record(1, at: 0)
        history.record(2, at: 3)

        #expect(history.display(at: 0) == 2)

        history.removeAll()
        #expect(history.display(at: 3) == nil)
    }
}
