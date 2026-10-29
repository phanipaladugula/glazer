import Foundation

/// Holds a display switch back while the user is typing.
///
/// ``GazeEngine`` decides which display the user faces. Typing is a stronger signal of
/// where they're working, so while they type, focus stays put however their head turns.
/// Once they've paused for ``pause``, a held-back switch goes ahead, so focus is already
/// on the new display when they start typing again. If they face the original display
/// again before pausing, the switch is dropped.
public struct TypingGuard: Sendable {
    /// How long without a keystroke counts as having stopped typing.
    public let pause: TimeInterval

    /// The display waiting for the user to stop typing.
    public private(set) var heldDisplay: Display.ID?

    private var focusedDisplay: Display.ID?
    private var lastKeystroke: TimeInterval = -.infinity

    public init(focusedDisplay: Display.ID?, pause: TimeInterval = 1.0) {
        self.focusedDisplay = focusedDisplay
        self.pause = pause
    }

    /// Records a keystroke.
    public mutating func keyPressed(at timestamp: TimeInterval) {
        lastKeystroke = timestamp
    }

    /// The user now faces `display`. Returns it if focus should move there now, or `nil`
    /// if focus stays, because it's already there or the user is typing.
    public mutating func userFaces(_ display: Display.ID, at timestamp: TimeInterval) -> Display.ID? {
        heldDisplay = display == focusedDisplay ? nil : display
        return release(at: timestamp)
    }

    /// Returns the held-back display once the user has stopped typing. Call regularly,
    /// such as on every camera frame.
    public mutating func release(at timestamp: TimeInterval) -> Display.ID? {
        guard let heldDisplay, timestamp - lastKeystroke >= pause else { return nil }
        focusedDisplay = heldDisplay
        self.heldDisplay = nil
        return heldDisplay
    }

    /// The user moved focus themselves, such as by moving the pointer to `display`.
    public mutating func userFocused(_ display: Display.ID) {
        focusedDisplay = display
        heldDisplay = nil
    }
}
