import GlazerCore
import Observation

/// The state of a calibration run, shown by the overlays on each display.
///
/// Each display shows a dot at its centre, then at each corner. The user looks at the dot
/// and clicks it, and Glazer records where their head points while the dot fills. The dots
/// give each display's extent, not just its middle, so Glazer knows where one display ends
/// and the next begins.
@MainActor
@Observable
final class CalibrationSession {
    /// One dot: a spot on a display.
    struct Target: Hashable {
        let display: Display
        let spot: Calibration.Spot
    }

    enum Phase: Equatable {
        /// Asking the user to look at and click `targets[index]`.
        case recording(index: Int)
        case finished(Calibration)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Two displays were recorded at nearly the same head pose.
        case displaysTooClose
        /// The camera stopped part way, such as when it was disconnected.
        case cameraStopped
    }

    enum Hint: Equatable {
        case none
        case cantSeeYou
        case tooDark
        case notRecognized
        case holdStill
        /// Still facing the display just recorded.
        case turnToDisplay
    }

    /// How far, in degrees, the head must turn from the previous display before the next
    /// one is recorded. The same separation calibration requires between displays.
    private let minimumTurn = 6.0
    private var hasTurned = true

    /// Displays in calibration order: top to bottom, then left to right.
    let displays: [Display]
    /// Every dot, in order: each display's centre, then its corners clockwise from the top
    /// left.
    let targets: [Target]
    private(set) var phase: Phase = .recording(index: 0)
    private(set) var progress = 0.0
    private(set) var hint: Hint = .none
    /// Whether the user has clicked the current dot, so it's recording.
    private(set) var isArmed = false

    private var recorder = CalibrationSession.makeRecorder()
    private var points: [Calibration.Point] = []

    /// How much head turn and tilt count, from how the displays are arranged.
    let weights: AxisWeights

    init(displays: [Display]) {
        self.displays = displays.inReadingOrder
        targets = self.displays.flatMap { display in
            Calibration.Spot.allCases.map { Target(display: display, spot: $0) }
        }
        weights = AxisWeights(arranging: displays)
    }

    var currentTarget: Target? {
        guard case .recording(let index) = phase else { return nil }
        return targets[index]
    }

    var currentDisplay: Display? {
        currentTarget?.display
    }

    /// The current dot's number on its display, from 1, and how many dots each display has.
    var dotStep: (number: Int, count: Int)? {
        guard case .recording(let index) = phase else { return nil }
        let count = Calibration.Spot.allCases.count
        return (index % count + 1, count)
    }

    /// The current display's number, from 1.
    var displayStep: Int? {
        guard let display = currentDisplay else { return nil }
        return (displays.firstIndex(of: display) ?? 0) + 1
    }

    /// The user clicked the current dot, or pressed Space: record it.
    func confirm() {
        guard case .recording = phase, !isArmed else { return }
        isArmed = true
        recorder = Self.makeRecorder()
        progress = 0
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

        // Don't record the next display until the user has turned away from the last one,
        // or clicking without turning would record the previous display's pose again.
        if !hasTurned, let previous = previousCentre(before: index) {
            guard pose.distance(to: previous, weights: weights) >= minimumTurn else {
                hint = isArmed ? .turnToDisplay : .none
                progress = 0
                return
            }
            hasTurned = true
        }

        guard isArmed else {
            hint = .none
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
            let target = targets[index]
            points.append(Calibration.Point(displayID: target.display.id, spot: target.spot, pose: pose))
            advance(from: index)
        }
    }

    /// The centre pose of the display before `targets[index]`'s, when it's the first dot on
    /// a new display.
    private func previousCentre(before index: Int) -> HeadPose? {
        guard index > 0, targets[index].spot == .centre else { return nil }
        let previous = targets[index - 1].display.id
        return points.first { $0.displayID == previous && $0.spot == .centre }?.pose
    }

    /// A click confirms the user is looking at the dot, so recording needs only a short
    /// settle and a second of poses.
    private static func makeRecorder() -> CalibrationRecorder {
        var configuration = CalibrationRecorder.Configuration()
        configuration.settleDuration = 0.25
        configuration.recordDuration = 0.9
        configuration.minimumSamples = 6
        return CalibrationRecorder(configuration: configuration)
    }

    /// The camera stopped part way.
    func cameraStopped() {
        guard case .recording = phase else { return }
        phase = .failed(.cameraStopped)
    }

    /// Starts over from the first display.
    func restart() {
        points.removeAll()
        hasTurned = true
        isArmed = false
        recorder = Self.makeRecorder()
        progress = 0
        hint = .none
        phase = .recording(index: 0)
    }

    private func advance(from index: Int) {
        progress = 0
        hint = .none
        isArmed = false
        recorder = Self.makeRecorder()

        guard index + 1 >= targets.count else {
            hasTurned = targets[index + 1].display == targets[index].display
            phase = .recording(index: index + 1)
            return
        }

        let calibration = Calibration(points: points)
        phase = calibration.issue(weights: weights) == nil ? .finished(calibration) : .failed(.displaysTooClose)
    }
}
