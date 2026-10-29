import Foundation

/// Recognises a deliberate double-press of one modifier key.
///
/// A double-press is two taps of the key in quick succession, with nothing else pressed in
/// between. A tap is a press released quickly. So holding the key as a modifier (fn and an
/// arrow, ⌥ while typing) never counts, and neither does pressing it once.
public struct DoublePressDetector: Sendable {
    public enum Event: Equatable, Sendable {
        /// The watched key went down.
        case keyDown
        /// The watched key came up.
        case keyUp
        /// Any other key or modifier was pressed.
        case otherKey
    }

    /// The longest a press can last and still be a tap, in seconds.
    public var maximumTapDuration: TimeInterval = 0.35
    /// The longest gap allowed between the first tap ending and the second starting.
    public var maximumGap: TimeInterval = 0.4

    private var pressedAt: TimeInterval?
    private var lastTapEndedAt: TimeInterval?
    /// Set when the second tap's press arrived in time; it counts once released.
    private var secondTapPending = false

    public init() {}

    /// Adds an event, and returns `true` when it completes a double-press.
    public mutating func add(_ event: Event, at timestamp: TimeInterval) -> Bool {
        switch event {
        case .otherKey:
            reset()
            return false

        case .keyDown:
            if let lastTapEndedAt, timestamp - lastTapEndedAt <= maximumGap {
                secondTapPending = true
            } else {
                secondTapPending = false
                lastTapEndedAt = nil
            }
            pressedAt = timestamp
            return false

        case .keyUp:
            guard let pressedAt, timestamp - pressedAt <= maximumTapDuration else {
                // Held too long: it was used as a modifier, not tapped.
                reset()
                return false
            }
            self.pressedAt = nil
            if secondTapPending {
                reset()
                return true
            }
            lastTapEndedAt = timestamp
            return false
        }
    }

    public mutating func reset() {
        pressedAt = nil
        lastTapEndedAt = nil
        secondTapPending = false
    }
}
