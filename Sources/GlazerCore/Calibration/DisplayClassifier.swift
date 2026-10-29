import Foundation

/// Decides which display the user is facing, and when to switch.
///
/// The nearest display wins, but only after a margin and a dwell time: the new display must
/// be clearly nearer than the current one, for long enough that it isn't a glance. Looking
/// far away from every display, such as down at a phone, changes nothing.
///
/// A display's distance is to the region its centre and corner poses span, so facing
/// anywhere on it counts as facing it. Where regions overlap, the nearer centre decides.
public struct DisplayClassifier: Sendable {
    public struct Configuration: Sendable {
        /// How long the user must face another display before focus moves.
        public var dwell: TimeInterval = 0.5
        /// How much nearer, in degrees, another display must be than the current one.
        public var margin: Double = 3
        /// Poses further than this, in degrees, from every display are ignored.
        public var maximumDistance: Double = 40
        /// How much head turn and head tilt count. Set from the display arrangement; see
        /// ``AxisWeights/init(arranging:floor:)``.
        public var weights = AxisWeights.sideBySide

        public init() {}
    }

    public var configuration: Configuration
    public let calibration: Calibration
    private let regions: [(id: Display.ID, region: PoseRegion, centre: HeadPose)]

    /// The display the user is facing, once decided.
    public private(set) var focused: Display.ID?

    private var candidate: (id: Display.ID, since: TimeInterval)?
    /// The display the user was facing when they moved focus by hand. Facing it doesn't
    /// count as a reason to switch until they turn to another display.
    private var ignored: Display.ID?
    /// The display nearest the latest pose, without waiting for the dwell: the display the
    /// user is facing right now. `nil` when they face none of them.
    public private(set) var nearest: Display.ID?

    public init(calibration: Calibration, configuration: Configuration = Configuration()) {
        self.calibration = calibration
        self.configuration = configuration
        regions = calibration.displayIDs.compactMap { id in
            guard let region = calibration.region(for: id), let centre = calibration.pose(for: id) else { return nil }
            return (id, region, centre)
        }
    }

    /// Adds a pose and returns the display in focus, which may have just changed.
    @discardableResult
    public mutating func update(with pose: HeadPose, at timestamp: TimeInterval) -> Display.ID? {
        let weights = configuration.weights
        let distances = regions.map {
            (
                id: $0.id, distance: $0.region.distance(to: pose, weights: weights),
                centre: pose.distance(to: $0.centre, weights: weights)
            )
        }
        guard let nearest = distances.min(by: { ($0.distance, $0.centre) < ($1.distance, $1.centre) }),
            nearest.distance <= configuration.maximumDistance
        else {
            candidate = nil
            self.nearest = nil
            return focused
        }
        self.nearest = nearest.id

        // After a manual move, wait for a new head turn before switching.
        if let ignored {
            if nearest.id == ignored {
                candidate = nil
                return focused
            }
            self.ignored = nil
        }

        let current = distances.first { $0.id == focused }
        if let current, nearest.id == current.id || nearest.distance + configuration.margin >= current.distance {
            candidate = nil
            return focused
        }

        if candidate?.id != nearest.id {
            candidate = (nearest.id, timestamp)
        }
        if let candidate, timestamp - candidate.since >= configuration.dwell {
            focused = candidate.id
            self.candidate = nil
        }
        return focused
    }

    /// Forgets any display that was about to take focus. Call when the user is lost, so a
    /// half-finished dwell doesn't complete the moment they are found again.
    public mutating func cancelPendingSwitch() {
        candidate = nil
    }

    /// Sets the focused display directly, such as when the user clicks on a display.
    public mutating func setFocused(_ id: Display.ID?) {
        focused = id
        candidate = nil
    }

    /// The user moved focus to `id` themselves, such as with the mouse, while possibly
    /// facing another display. Focus stays there until they turn their head to a
    /// different display than the one they're facing now.
    public mutating func userFocused(_ id: Display.ID) {
        setFocused(id)
        ignored = nearest == id ? nil : nearest
    }
}
