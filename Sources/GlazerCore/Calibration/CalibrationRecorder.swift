import Foundation

/// Records the head pose for one display during calibration.
///
/// The user is asked to look at the display. The recorder waits a moment for their head
/// to settle, then collects poses. If the head moved too much while recording, it starts
/// the recording again, so a calibration always comes from a steady look.
public struct CalibrationRecorder: Sendable {
    public struct Configuration: Sendable {
        /// Time allowed for the user's head to come to rest after the prompt.
        public var settleDuration: TimeInterval = 0.8
        /// How long poses are collected.
        public var recordDuration: TimeInterval = 1.5
        /// The largest typical deviation, in degrees, accepted from a steady look.
        public var maximumSpread: Double = 3.5
        /// The fewest samples a recording needs.
        public var minimumSamples = 8

        public init() {}
    }

    public enum Progress: Equatable, Sendable {
        /// Waiting for the head to settle.
        case settling
        /// Recording, with the fraction done from 0 to 1.
        case recording(Double)
        /// The head moved too much. Recording has started again.
        case unsteady
        /// Done, with the pose for this display.
        case finished(HeadPose)
    }

    public let configuration: Configuration
    public private(set) var progress: Progress = .settling

    private var startedAt: TimeInterval?
    private var recordingStartedAt: TimeInterval?
    private var samples: [HeadPose] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Adds a pose and returns the progress. Once finished, further poses are ignored.
    @discardableResult
    public mutating func add(_ pose: HeadPose, at timestamp: TimeInterval) -> Progress {
        if case .finished = progress { return progress }

        let startedAt = self.startedAt ?? timestamp
        self.startedAt = startedAt
        guard timestamp - startedAt >= configuration.settleDuration else {
            progress = .settling
            return progress
        }

        let recordingStartedAt = self.recordingStartedAt ?? timestamp
        self.recordingStartedAt = recordingStartedAt
        samples.append(pose)

        let elapsed = timestamp - recordingStartedAt
        guard elapsed >= configuration.recordDuration, samples.count >= configuration.minimumSamples else {
            progress = .recording(min(elapsed / configuration.recordDuration, 0.99))
            return progress
        }

        let yaws = samples.map(\.yaw)
        let pitches = samples.map(\.pitch)
        if Self.spread(yaws) > configuration.maximumSpread || Self.spread(pitches) > configuration.maximumSpread {
            samples.removeAll()
            self.recordingStartedAt = nil
            progress = .unsteady
            return progress
        }

        progress = .finished(HeadPose(yaw: Self.median(yaws), pitch: Self.median(pitches)))
        return progress
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The median absolute deviation: a measure of spread that ignores a few outliers,
    /// such as a single misdetected frame.
    static func spread(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }
}
