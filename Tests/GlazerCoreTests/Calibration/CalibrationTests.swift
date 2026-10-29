import Testing

@testable import GlazerCore

@Suite("Calibration")
struct CalibrationTests {
    let macBook = Display(id: macBookID, name: "Built-in", frame: .zero)
    let monitor = Display(id: monitorID, name: "LG", frame: .zero)

    @Test("Covers the displays it has points for")
    func covers() {
        #expect(twoDisplayCalibration.covers([macBook, monitor]))
    }

    @Test("Doesn't cover a display it has never seen")
    func missingDisplay() {
        let projector = Display(id: 3, name: "Projector", frame: .zero)
        #expect(!twoDisplayCalibration.covers([macBook, projector]))
    }

    @Test("A single display needs no calibration, so none covers it")
    func singleDisplay() {
        #expect(!twoDisplayCalibration.covers([macBook]))
    }

    @Test("Displays recorded at nearly the same pose are flagged")
    func tooClose() {
        let calibration = Calibration(points: [
            .init(displayID: 1, pose: HeadPose(yaw: 2, pitch: 0)),
            .init(displayID: 2, pose: HeadPose(yaw: 5, pitch: 1)),
        ])
        #expect(calibration.issue() == .tooClose(1, 2))
        #expect(twoDisplayCalibration.issue() == nil)
    }
}

@Suite("Calibration for connected displays")
struct CalibrationRestrictionTests {
    @Test("Points for disconnected displays are dropped")
    func dropsDisconnected() {
        let calibration = Calibration(points: [
            .init(displayID: 1, pose: HeadPose(yaw: -4, pitch: 0)),
            .init(displayID: 2, pose: HeadPose(yaw: 28, pitch: 0)),
            .init(displayID: 3, pose: HeadPose(yaw: 60, pitch: 0)),
        ])
        let connected = [Display(id: 1, name: "A", frame: .zero), Display(id: 2, name: "B", frame: .zero)]

        #expect(calibration.restricted(to: connected).points.map(\.displayID) == [1, 2])
    }

    @Test("Facing where a disconnected display was never picks it")
    func neverPicksDisconnected() {
        let calibration = Calibration(points: [
            .init(displayID: 1, pose: HeadPose(yaw: -4, pitch: 0)),
            .init(displayID: 2, pose: HeadPose(yaw: 28, pitch: 0)),
            .init(displayID: 3, pose: HeadPose(yaw: 60, pitch: 0)),
        ])
        let connected = [Display(id: 1, name: "A", frame: .zero), Display(id: 2, name: "B", frame: .zero)]
        var classifier = DisplayClassifier(calibration: calibration.restricted(to: connected))
        classifier.setFocused(1)

        classifier.update(with: HeadPose(yaw: 60, pitch: 0), at: 0)
        #expect(classifier.update(with: HeadPose(yaw: 60, pitch: 0), at: 1) != 3)
    }
}
