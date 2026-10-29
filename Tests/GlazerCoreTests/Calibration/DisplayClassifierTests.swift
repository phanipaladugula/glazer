import Testing

@testable import GlazerCore

@Suite("DisplayClassifier")
struct DisplayClassifierTests {
    let atMacBook = HeadPose(yaw: -3, pitch: -7)
    let atMonitor = HeadPose(yaw: 27, pitch: 1)

    func classifier(focused: Display.ID? = macBookID) -> DisplayClassifier {
        var classifier = DisplayClassifier(calibration: twoDisplayCalibration)
        classifier.setFocused(focused)
        return classifier
    }

    @Test("Facing the focused display changes nothing")
    func staysPut() {
        var classifier = classifier()
        #expect(classifier.update(with: atMacBook, at: 0) == macBookID)
        #expect(classifier.update(with: atMacBook, at: 2) == macBookID)
    }

    @Test("Focus moves only after facing another display for the dwell time")
    func dwell() {
        var classifier = classifier()
        #expect(classifier.update(with: atMonitor, at: 0) == macBookID)
        #expect(classifier.update(with: atMonitor, at: 0.4) == macBookID)
        #expect(classifier.update(with: atMonitor, at: 0.5) == monitorID)
    }

    @Test("A glance back and forth doesn't switch")
    func glance() {
        var classifier = classifier()
        classifier.update(with: atMonitor, at: 0)
        classifier.update(with: atMonitor, at: 0.3)
        classifier.update(with: atMacBook, at: 0.4)
        #expect(classifier.update(with: atMonitor, at: 0.6) == macBookID)
    }

    @Test("Halfway between displays, focus stays where it is")
    func margin() {
        var classifier = classifier()
        let between = HeadPose(yaw: 13, pitch: -3)
        classifier.update(with: between, at: 0)
        #expect(classifier.update(with: between, at: 2) == macBookID)
    }

    @Test("Looking far away from every display changes nothing")
    func lookingAway() {
        var classifier = classifier()
        let atPhone = HeadPose(yaw: -10, pitch: -60)
        classifier.update(with: atPhone, at: 0)
        #expect(classifier.update(with: atPhone, at: 2) == macBookID)
    }

    @Test("With nothing focused yet, the faced display is adopted after the dwell")
    func initialFocus() {
        var classifier = classifier(focused: nil)
        #expect(classifier.update(with: atMonitor, at: 0) == nil)
        #expect(classifier.update(with: atMonitor, at: 0.6) == monitorID)
    }

    @Test("A cancelled switch starts its dwell over")
    func cancel() {
        var classifier = classifier()
        classifier.update(with: atMonitor, at: 0)
        classifier.cancelPendingSwitch()
        #expect(classifier.update(with: atMonitor, at: 0.5) == macBookID)
        #expect(classifier.update(with: atMonitor, at: 1.0) == monitorID)
    }
}

@Suite("DisplayClassifier, manual moves")
struct DisplayClassifierManualMoveTests {
    let atMacBook = HeadPose(yaw: -3, pitch: -7)
    let atMonitor = HeadPose(yaw: 27, pitch: 1)

    @Test("Moving the pointer to the other display by hand isn't undone while the head stays put")
    func manualMoveSticks() {
        var classifier = DisplayClassifier(calibration: twoDisplayCalibration)
        classifier.setFocused(macBookID)
        classifier.update(with: atMacBook, at: 0)

        classifier.userFocused(monitorID)
        classifier.update(with: atMacBook, at: 0.1)
        #expect(classifier.update(with: atMacBook, at: 2) == monitorID)
    }

    @Test("After a manual move, a new head turn switches as usual")
    func turnAfterManualMove() {
        var classifier = DisplayClassifier(calibration: twoDisplayCalibration)
        classifier.setFocused(macBookID)
        classifier.update(with: atMacBook, at: 0)
        classifier.userFocused(monitorID)

        classifier.update(with: atMonitor, at: 1)
        classifier.update(with: atMacBook, at: 1.1)
        #expect(classifier.update(with: atMacBook, at: 1.7) == macBookID)
    }
}
