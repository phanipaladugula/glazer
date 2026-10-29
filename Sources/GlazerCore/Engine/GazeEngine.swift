import Foundation

/// Glazer's decision pipeline: from camera frames to "focus this display".
///
/// ```
/// Frame ─▶ UserTracker ─▶ HeadPoseFilter ─▶ DisplayClassifier ─▶ Output
///   └────▶ LightMeter ───────────────────────────────────────────▲
/// ```
///
/// The engine is a plain value with no clock, camera or UI, so the whole pipeline can be
/// tested with invented frames.
public struct GazeEngine: Sendable {
    public enum Status: Equatable, Sendable {
        /// Following the user.
        case following
        /// No face in view. The user may have stepped away.
        case searching
        /// Too dark to find a face.
        case tooDark
        /// Faces are in view, but none is the enrolled user.
        case notRecognized
    }

    public struct Output: Equatable, Sendable {
        public var status: Status
        /// The user's smoothed head pose, while they're being followed.
        public var pose: HeadPose?
        public var lightLevel: LightLevel
        /// The display the user is facing, once decided.
        public var focusedDisplay: Display.ID?
        /// Set on the frame where focus moved to another display.
        public var switchedTo: Display.ID?
    }

    public private(set) var tracker: UserTracker
    public private(set) var classifier: DisplayClassifier?

    private var filter = HeadPoseFilter()
    private var lightMeter = LightMeter()
    private var status: Status = .searching
    private var pose: HeadPose?

    /// - Parameters:
    ///   - calibration: Without one, the engine still follows the user and reports their
    ///     pose (which calibration itself needs), but never switches displays.
    ///   - verifier: Set to follow only the enrolled user.
    public init(
        calibration: Calibration?,
        verifier: IdentityVerifier? = nil,
        tracking: UserTracker.Configuration = UserTracker.Configuration(),
        classification: DisplayClassifier.Configuration = DisplayClassifier.Configuration()
    ) {
        tracker = UserTracker(configuration: tracking, verifier: verifier)
        classifier = calibration.map { DisplayClassifier(calibration: $0, configuration: classification) }
    }

    /// Whether the next frame should include face signatures. See
    /// ``UserTracker/needsSignatures(at:)``.
    public func needsSignatures(at timestamp: TimeInterval) -> Bool {
        tracker.needsSignatures(at: timestamp)
    }

    /// Sets the display in focus without a switch, such as at start-up, from where the
    /// pointer is.
    public mutating func setFocusedDisplay(_ id: Display.ID?) {
        classifier?.setFocused(id)
    }

    /// Changes how long the user must face another display before it takes focus, without
    /// losing who is being followed or where they're looking.
    public mutating func setDwell(_ dwell: TimeInterval) {
        classifier?.configuration.dwell = dwell
    }

    public mutating func process(_ frame: Frame) -> Output {
        let lightLevel = lightMeter.update(brightness: frame.brightness)
        let previousFocus = classifier?.focused

        switch tracker.update(with: frame) {
        case .user(let face):
            let smoothed = filter.filter(face.pose, at: frame.timestamp)
            pose = smoothed
            status = .following
            classifier?.update(with: smoothed, at: frame.timestamp)
        case .holding, .checking:
            break
        case .noFace:
            loseUser()
            status = lightLevel == .tooDark ? .tooDark : .searching
        case .notRecognized:
            loseUser()
            status = .notRecognized
        }

        let focused = classifier?.focused
        return Output(
            status: status,
            pose: status == .following ? pose : nil,
            lightLevel: lightLevel,
            focusedDisplay: focused,
            switchedTo: focused != previousFocus ? focused : nil
        )
    }

    private mutating func loseUser() {
        pose = nil
        filter.reset()
        classifier?.cancelPendingSwitch()
    }
}
