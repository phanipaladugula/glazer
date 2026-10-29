import GlazerCore
import Observation

/// The state of a calibration run, shown by the overlays on each display.
@MainActor
@Observable
final class CalibrationSession {
    enum Phase: Equatable {
        /// Asking the user to look at `displays[index]`.
        case recording(index: Int)
        case finished(Calibration)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Two displays were recorded at nearly the same head pose.
        case displaysTooClose
    }

    enum Hint: Equatable {
        case none
        case cantSeeYou
        case tooDark
        case notRecognized
        case holdStill
    }

    /// Displays in calibration order, left to right.
    let displays: [Display]
    private(set) var phase: Phase = .recording(index: 0)
    private(set) var progress = 0.0
    private(set) var hint: Hint = .none

    private var recorder = CalibrationRecorder()
    private var points: [Calibration.Point] = []

    init(displays: [Display]) {
        self.displays = displays.sorted { $0.frame.minX < $1.frame.minX }
    }

    var currentDisplay: Display? {
        guard case .recording(let index) = phase else { return nil }
        return displays[index]
    }

    /// Feeds one frame's engine output into the run.
    func add(_ output: GazeEngine.Output?, at timestamp: Double) {
        guard case .recording(let index) = phase, let output else { return }

        guard let pose = output.pose else {
            hint =
                switch output.status {
                case .tooDark: .tooDark
                case .notRecognized: .notRecognized
                case .following, .searching: .cantSeeYou
                }
            return
        }

        switch recorder.add(pose, at: timestamp) {
        case .settling:
            hint = .none
            progress = 0
        case .recording(let fraction):
            hint = .none
            progress = fraction
        case .unsteady:
            hint = .holdStill
            progress = 0
        case .finished(let pose):
            points.append(Calibration.Point(displayID: displays[index].id, pose: pose))
            advance(from: index)
        }
    }

    /// Starts over from the first display.
    func restart() {
        points.removeAll()
        recorder = CalibrationRecorder()
        progress = 0
        hint = .none
        phase = .recording(index: 0)
    }

    private func advance(from index: Int) {
        progress = 0
        hint = .none
        recorder = CalibrationRecorder()

        guard index + 1 >= displays.count else {
            phase = .recording(index: index + 1)
            return
        }

        let calibration = Calibration(points: points)
        phase = calibration.issue() == nil ? .finished(calibration) : .failed(.displaysTooClose)
    }
}
