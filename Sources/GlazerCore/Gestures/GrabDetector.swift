import CoreGraphics
import Foundation

/// Recognises a grab (an open hand closing into a fist) and the drop that follows (the
/// fist opening again).
///
/// ```
///            open, then closed and still          open
///   idle ─────────────────────────────▶ holding ──────▶ idle  (dropped)
///                                          │
///                                          └── too long, or hand gone ─▶ idle (cancelled)
/// ```
///
/// A fist on its own never counts: the hand must be seen open just before, and stay in
/// about the same place while it closes. That keeps out a hand that's already closed,
/// such as one holding a mug or propping up a chin, and a hand that closes while reaching
/// for something.
public struct GrabDetector: Sendable {
    public struct Configuration: Sendable {
        /// Openness at and above which a hand counts as open.
        public var openAbove = 0.7
        /// Openness at and below which a hand counts as a fist.
        public var closedBelow = 0.3
        /// The least confidence for a hand to count at all.
        public var minimumConfidence = 0.5
        /// The fist must start closing within this long of the hand being seen open.
        public var closeWithin: TimeInterval = 0.8
        /// How long the fist must stay closed to count as a grab.
        public var closedFor: TimeInterval = 0.25
        /// Openness at and above which a held fist counts as opened, for a drop. Lower than
        /// ``openAbove``: once a grab is held, any clear opening is the drop, so it needn't
        /// wait for the fingers to spread fully.
        public var dropAbove = 0.6
        /// How long the hand must stay open to count as a drop. Readings aren't smoothed
        /// while a grab is held, so this alone keeps one misread frame from dropping it.
        public var openFor: TimeInterval = 0.15
        /// How far the hand may move while closing, as a share of the image width.
        public var maximumTravel = 0.15
        /// The longest a grab is held before it's given up.
        public var holdLimit: TimeInterval = 15
        /// How long the hand may be out of view while held before the grab is given up.
        public var lostLimit: TimeInterval = 6
        /// The pause after a drop or a cancel before the next grab can start.
        public var cooldown: TimeInterval = 1

        public init() {}
    }

    public enum Event: Equatable, Sendable {
        /// The hand closed. `startedAt` is when it was last seen open, the moment the
        /// user decided to grab.
        case grabbed(startedAt: TimeInterval)
        /// The hand opened. `startedAt` is when it started opening.
        case dropped(startedAt: TimeInterval)
        /// The grab was held too long, or the hand went out of view.
        case cancelled
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case holding
    }

    enum Shape {
        case open
        case closed
        case between
    }

    public var configuration: Configuration
    public var calibration: HandCalibration
    public private(set) var phase: Phase = .idle
    /// The latest openness, smoothed, or `nil` with no hand in view.
    public private(set) var openness: Double?

    private var recent: [Double] = []
    /// The latest openness before smoothing.
    private var latest = 0.0
    private var lastOpen: (time: TimeInterval, centre: CGPoint)?
    private var closedSince: TimeInterval?
    private var openSince: TimeInterval?
    private var grabbedAt: TimeInterval = 0
    private var lastSeen: TimeInterval = 0
    private var quietUntil = -TimeInterval.infinity

    public init(calibration: HandCalibration, configuration: Configuration = Configuration()) {
        self.calibration = calibration
        self.configuration = configuration
    }

    /// Adds the hand seen at `timestamp`, or `nil` if none was, and returns an event when
    /// one happens.
    public mutating func update(_ hand: HandReading?, at timestamp: TimeInterval) -> Event? {
        let hand = hand.flatMap { $0.confidence >= configuration.minimumConfidence ? $0 : nil }
        let shape = hand.map { self.shape(of: $0) }
        if hand == nil {
            recent.removeAll()
            openness = nil
        }

        switch phase {
        case .idle:
            guard timestamp >= quietUntil else { return nil }
            return idle(hand, shape, at: timestamp)
        case .holding:
            return holding(hand, shape, at: timestamp)
        }
    }

    /// Holds a grab made on a linked Mac, so this Mac's camera watches for the drop, from
    /// `timestamp`. Ignored if this Mac is already holding one.
    public mutating func adoptHold(at timestamp: TimeInterval) {
        guard phase == .idle else { return }
        phase = .holding
        grabbedAt = timestamp
        lastSeen = timestamp
        openSince = nil
    }

    /// Gives up a grab in progress, such as when gestures are turned off.
    public mutating func reset() {
        phase = .idle
        recent.removeAll()
        openness = nil
        lastOpen = nil
        closedSince = nil
        openSince = nil
    }

    private mutating func idle(_ hand: HandReading?, _ shape: Shape?, at timestamp: TimeInterval) -> Event? {
        guard let hand, let shape else {
            closedSince = nil
            return nil
        }
        switch shape {
        case .open:
            // Smoothing lags a frame behind: only a frame that's open itself says where
            // the open hand was.
            if latest >= configuration.openAbove {
                lastOpen = (timestamp, hand.centre)
            }
            closedSince = nil
        case .between:
            // On its way between shapes: neither starts nor breaks anything.
            break
        case .closed:
            let since = closedSince ?? timestamp
            guard let lastOpen, since - lastOpen.time <= configuration.closeWithin,
                hand.centre.distance(to: lastOpen.centre) <= configuration.maximumTravel
            else {
                // A fist that wasn't just an open hand, or that moved: not a grab. Forget
                // the open hand, so this fist can't turn into one later.
                self.lastOpen = nil
                closedSince = nil
                return nil
            }
            closedSince = since
            if timestamp - since >= configuration.closedFor {
                phase = .holding
                grabbedAt = timestamp
                lastSeen = timestamp
                openSince = nil
                closedSince = nil
                self.lastOpen = nil
                return .grabbed(startedAt: lastOpen.time)
            }
        }
        return nil
    }

    private mutating func holding(_ hand: HandReading?, _ shape: Shape?, at timestamp: TimeInterval) -> Event? {
        if hand != nil {
            lastSeen = timestamp
        }
        if timestamp - grabbedAt > configuration.holdLimit || timestamp - lastSeen > configuration.lostLimit {
            finish(at: timestamp)
            return .cancelled
        }
        // Unsmoothed, so the drop follows the hand without waiting on older frames.
        let opened = hand != nil && latest >= configuration.dropAbove
        switch opened ? .open : shape {
        case .open:
            let since = openSince ?? timestamp
            openSince = since
            if timestamp - since >= configuration.openFor {
                finish(at: timestamp)
                return .dropped(startedAt: since)
            }
        case .closed, nil:
            openSince = nil
        case .between:
            break
        }
        return nil
    }

    private mutating func finish(at timestamp: TimeInterval) {
        reset()
        quietUntil = timestamp + configuration.cooldown
    }

    /// The hand's shape, from the median of the last three readings, so one misread
    /// frame can't start or end a grab.
    private mutating func shape(of hand: HandReading) -> Shape {
        latest = calibration.openness(of: hand.features)
        recent.append(latest)
        if recent.count > 3 {
            recent.removeFirst()
        }
        let openness = Statistics.median(recent)
        self.openness = openness
        if openness >= configuration.openAbove { return .open }
        if openness <= configuration.closedBelow { return .closed }
        return .between
    }
}
