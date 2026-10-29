import Foundation

/// Records the user's open hand and fist for a ``HandCalibration``.
///
/// The user is asked for each shape twice, alternating, so the calibration sees the hand
/// held a little differently each time, as it will be in use. Each shape is recorded once
/// the hand has been in view long enough to settle. If the hand leaves the view while a
/// shape is being recorded, that shape starts again.
public struct HandCalibrationRecorder: Sendable {
    public enum Shape: Equatable, Sendable {
        case open
        case fist
    }

    public struct Configuration: Sendable {
        /// The shapes asked for, in order.
        public var shapes: [Shape] = [.open, .fist, .open, .fist]
        /// Time allowed for the hand to settle into the shape once it's in view.
        public var settleDuration: TimeInterval = 0.7
        /// How long each shape is recorded.
        public var recordDuration: TimeInterval = 1.2
        /// How long the hand may be out of view before the shape starts again. A frame or
        /// two without the hand is normal.
        public var allowedGap: TimeInterval = 0.4

        public init() {}
    }

    public enum Progress: Equatable, Sendable {
        /// Waiting for the hand to come into view in `shape`.
        case waiting(Shape)
        /// Recording `shape`, with the fraction done from 0 to 1.
        case recording(Shape, Double)
        case finished(HandCalibration)
        case failed(HandCalibration.Problem)
    }

    public let configuration: Configuration
    public private(set) var progress: Progress

    /// Which of ``Configuration/shapes`` is being recorded.
    public private(set) var step = 0

    private var seenSince: TimeInterval?
    private var lastSeen: TimeInterval?
    private var recordingSince: TimeInterval?
    private var current: [HandFeatures] = []
    private var open: [HandFeatures] = []
    private var fist: [HandFeatures] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        progress = configuration.shapes.first.map(Progress.waiting) ?? .failed(.tooFewReadings)
    }

    /// The fraction of all the shapes done, from 0 to 1.
    public var fractionDone: Double {
        let count = Double(configuration.shapes.count)
        switch progress {
        case .waiting: return Double(step) / count
        case .recording(_, let fraction): return (Double(step) + fraction) / count
        case .finished, .failed: return 1
        }
    }

    /// Adds the hand seen at `timestamp`, or `nil` if none was, and returns the progress.
    @discardableResult
    public mutating func add(_ hand: HandReading?, at timestamp: TimeInterval) -> Progress {
        guard step < configuration.shapes.count else { return progress }
        let shape = configuration.shapes[step]

        guard let hand else {
            if let lastSeen, timestamp - lastSeen > configuration.allowedGap {
                restartShape(shape)
            }
            return progress
        }
        lastSeen = timestamp
        let seenSince = self.seenSince ?? timestamp
        self.seenSince = seenSince
        guard timestamp - seenSince >= configuration.settleDuration else { return progress }

        let recordingSince = self.recordingSince ?? timestamp
        self.recordingSince = recordingSince
        current.append(hand.features)

        let elapsed = timestamp - recordingSince
        guard elapsed >= configuration.recordDuration,
            current.count >= HandCalibration.minimumReadings / 2
        else {
            progress = .recording(shape, min(elapsed / configuration.recordDuration, 0.99))
            return progress
        }

        switch shape {
        case .open: open += current
        case .fist: fist += current
        }
        step += 1
        restartShape(step < configuration.shapes.count ? configuration.shapes[step] : shape)

        if step == configuration.shapes.count {
            do {
                progress = .finished(try HandCalibration.fit(open: open, fist: fist))
            } catch {
                progress = .failed(error)
            }
        }
        return progress
    }

    private mutating func restartShape(_ shape: Shape) {
        seenSince = nil
        lastSeen = nil
        recordingSince = nil
        current.removeAll()
        progress = .waiting(shape)
    }
}
