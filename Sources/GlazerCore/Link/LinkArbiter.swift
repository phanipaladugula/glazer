import Foundation

/// Decides which Mac the user is at: this one, or one of its linked Macs.
///
/// Every Mac reports whether the user faces it (``Presence``), judged by its own camera
/// against its own calibration. Every linked Mac runs this same rule on the same reports:
///
/// - this Mac faced: the user is here;
/// - otherwise, the linked Mac faced most squarely, among recent reports, after a short
///   dwell, so a glance doesn't count;
/// - no Mac faced, such as when the user looks at a phone: no change.
///
/// The shortcut can also move the user to a Mac (``choose(_:)``); that holds until they
/// turn to a different Mac than the one they were facing then.
public struct LinkArbiter: Sendable {
    public struct Configuration: Sendable {
        /// How long another Mac must be faced before the user counts as there.
        public var dwell: TimeInterval = 0.4
        /// A report older than this no longer counts. Reports come at least every second.
        public var staleAfter: TimeInterval = 2.5

        public init() {}
    }

    /// Where the user is: `nil` for this Mac, otherwise a linked Mac's ID.
    public private(set) var target: String?

    public var configuration: Configuration

    private var local = Presence.unknown
    private var localTime = -TimeInterval.infinity
    private var peers: [String: (presence: Presence, time: TimeInterval)] = [:]
    private var candidate: (target: String?, since: TimeInterval)?
    /// Facing this doesn't move the user, after a choice with the shortcut, until they
    /// face something else. `.some(nil)` is this Mac.
    private var ignored: String??

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func updateLocal(_ presence: Presence, at timestamp: TimeInterval) {
        local = presence
        localTime = timestamp
    }

    public mutating func update(peer: String, _ presence: Presence, at timestamp: TimeInterval) {
        peers[peer] = (presence, timestamp)
    }

    /// Forgets a Mac, such as when its link drops. If the user was there, they're back here.
    public mutating func remove(peer: String) {
        peers[peer] = nil
        if target == peer {
            target = nil
        }
        if candidate?.target == peer {
            candidate = nil
        }
    }

    /// Moves the user to `target` straight away, such as with the shortcut.
    public mutating func choose(_ target: String?, at timestamp: TimeInterval) {
        ignored = faced(at: timestamp)
        self.target = target
        candidate = nil
    }

    /// The Macs linked and reporting.
    public var peerIDs: [String] {
        peers.keys.sorted()
    }

    /// Re-decides where the user is, and returns it.
    @discardableResult
    public mutating func decide(at timestamp: TimeInterval) -> String? {
        guard let faced = faced(at: timestamp) else {
            // No Mac faced: nothing changes.
            candidate = nil
            return target
        }
        if let ignored {
            if ignored == faced {
                candidate = nil
                return target
            }
            self.ignored = nil
        }
        guard faced != target else {
            candidate = nil
            return target
        }
        if candidate == nil || candidate?.target != faced {
            candidate = (faced, timestamp)
        }
        // Coming back to this Mac needs no dwell: its own camera says so, and lingering
        // elsewhere would send typing to the wrong Mac.
        if faced == nil || timestamp - (candidate?.since ?? timestamp) >= configuration.dwell {
            target = faced
            candidate = nil
        }
        return target
    }

    /// The Mac faced now: `.some(nil)` for this one, `.some(id)` for a linked one, `nil`
    /// for none.
    private func faced(at timestamp: TimeInterval) -> String?? {
        if local.isFaced, timestamp - localTime <= configuration.staleAfter {
            return .some(nil)
        }
        let best =
            peers
            .filter { $0.value.presence.isFaced && timestamp - $0.value.time <= configuration.staleAfter }
            .min {
                ($0.value.presence.distance ?? .infinity, $0.key) < ($1.value.presence.distance ?? .infinity, $1.key)
            }
        return best.map { .some($0.key) }
    }
}
