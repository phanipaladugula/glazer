import CoreGraphics
import Foundation

/// Records where the user holds their open hand for each display, for a ``HandAim``.
///
/// For each display in turn, the user turns to it and holds their open hand towards it.
/// Once the hand has been open and in view long enough to settle, its position relative
/// to the face is recorded. If the hand closes or leaves the view while recording, that
/// display starts again.
public struct HandAimRecorder: Sendable {
    public struct Configuration: Sendable {
        /// Time allowed for the hand to settle once it's in view and open.
        public var settleDuration: TimeInterval = 0.6
        /// How long each display is recorded.
        public var recordDuration: TimeInterval = 1.0
        /// How long the hand may be out of view, or not open, before the display starts
        /// again.
        public var allowedGap: TimeInterval = 0.4
        /// The least openness for the hand to count as held open.
        public var minimumOpenness = 0.6

        public init() {}
    }

    public enum Progress: Equatable, Sendable {
        /// Waiting for the open hand, held towards `display`.
        case waiting(Display.ID)
        /// Recording `display`, with the fraction done from 0 to 1.
        case recording(Display.ID, Double)
        case finished(HandAim)
        case failed(HandAim.Problem)
    }

    public let displays: [Display.ID]
    public let calibration: HandCalibration
    public let configuration: Configuration
    public private(set) var progress: Progress
    /// Which of ``displays`` is being recorded.
    public private(set) var step = 0

    private var seenSince: TimeInterval?
    private var lastSeen: TimeInterval?
    private var recordingSince: TimeInterval?
    private var current: [CGPoint] = []
    private var readings: [Display.ID: [CGPoint]] = [:]

    public init(
        displays: [Display.ID], calibration: HandCalibration, configuration: Configuration = Configuration()
    ) {
        self.displays = displays
        self.calibration = calibration
        self.configuration = configuration
        progress = displays.first.map(Progress.waiting) ?? .failed(.tooFewDisplays)
    }

    /// The fraction of all the displays done, from 0 to 1.
    public var fractionDone: Double {
        let count = Double(max(displays.count, 1))
        switch progress {
        case .waiting: return Double(step) / count
        case .recording(_, let fraction): return (Double(step) + fraction) / count
        case .finished, .failed: return 1
        }
    }

    /// Adds the user's hand and face seen at `timestamp`, either `nil` when not found, and
    /// returns the progress.
    @discardableResult
    public mutating func add(hand: HandReading?, face: CGRect?, at timestamp: TimeInterval) -> Progress {
        guard step < displays.count else { return progress }
        let display = displays[step]

        guard let hand, let face, calibration.openness(of: hand.features) >= configuration.minimumOpenness else {
            if let lastSeen, timestamp - lastSeen > configuration.allowedGap {
                restart(display)
            }
            return progress
        }
        lastSeen = timestamp
        let seenSince = self.seenSince ?? timestamp
        self.seenSince = seenSince
        guard timestamp - seenSince >= configuration.settleDuration else { return progress }

        let recordingSince = self.recordingSince ?? timestamp
        self.recordingSince = recordingSince
        current.append(UserHand.offset(of: hand, from: face))

        let elapsed = timestamp - recordingSince
        guard elapsed >= configuration.recordDuration, current.count >= HandAim.minimumReadings else {
            progress = .recording(display, min(elapsed / configuration.recordDuration, 0.99))
            return progress
        }

        readings[display] = current
        step += 1
        restart(step < displays.count ? displays[step] : display)
        if step == displays.count {
            do {
                progress = .finished(try HandAim.fit(readings))
            } catch {
                progress = .failed(error)
            }
        }
        return progress
    }

    private mutating func restart(_ display: Display.ID) {
        seenSince = nil
        lastSeen = nil
        recordingSince = nil
        current.removeAll()
        progress = .waiting(display)
    }
}
