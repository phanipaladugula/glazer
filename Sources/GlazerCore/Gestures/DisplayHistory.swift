import Foundation

/// Which display the user faced over the last few seconds.
///
/// A gesture is decided a moment after it starts, and a raised hand often hides the face
/// meanwhile. So a gesture goes to the display the user faced when it started, looked up
/// here, not the one they seem to face when it's recognised.
public struct DisplayHistory: Sendable {
    /// How far back the history goes.
    public var span: TimeInterval

    private var entries: [(time: TimeInterval, display: Display.ID)] = []

    public init(span: TimeInterval = 5) {
        self.span = span
    }

    /// Records that the user faced `display` at `timestamp`. `nil`, when no face is in
    /// view, isn't recorded, so the last display faced is kept.
    public mutating func record(_ display: Display.ID?, at timestamp: TimeInterval) {
        entries.removeAll { timestamp - $0.time > span }
        guard let display else { return }
        entries.append((timestamp, display))
    }

    /// The display faced at `timestamp`: the latest one recorded at or before it, or the
    /// earliest one after it if nothing was recorded before.
    public func display(at timestamp: TimeInterval) -> Display.ID? {
        entries.last { $0.time <= timestamp }?.display ?? entries.first?.display
    }

    /// The display recorded nearest to `timestamp`, if one was within `tolerance` of it.
    public func display(near timestamp: TimeInterval, within tolerance: TimeInterval) -> Display.ID? {
        entries
            .filter { abs($0.time - timestamp) <= tolerance }
            .min { abs($0.time - timestamp) < abs($1.time - timestamp) }?
            .display
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
