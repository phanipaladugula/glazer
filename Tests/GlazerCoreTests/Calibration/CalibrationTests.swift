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
