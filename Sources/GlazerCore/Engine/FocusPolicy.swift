import Foundation

/// When keyboard focus follows the user's gaze to another display.
public enum SwitchMode: String, CaseIterable, Codable, Sendable {
    /// The pointer moves as soon as the user faces another display. Keyboard focus follows
    /// when they start typing after a pause, so typing never goes to the wrong window,
    /// even while they look away to talk to someone.
    case automatic
    /// Nothing moves unless the hold key (Fn) is down.
    case holdKey
    /// The pointer and keyboard focus move together, as soon as the user faces another
    /// display.
    case immediate
}

/// Decides when the pointer and keyboard focus move, from where the user faces and when
/// they type.
///
/// ``GazeEngine`` decides which display the user faces. This decides what to do about it.
/// It is a plain value: it sees only "the user now faces this display", "a key was pressed
/// at this time" and "the hold key went down or up", never which key was pressed.
public struct FocusPolicy: Sendable {
    public enum Action: Equatable, Sendable {
        case movePointer(Display.ID)
        case moveKeyboardFocus(Display.ID)
    }

    public struct Configuration: Sendable {
        /// In automatic mode, how long the user must have stopped typing before a keystroke
        /// counts as a fresh start that can move keyboard focus. Shorter gaps are the same
        /// burst of typing, which always stays where it is.
        public var typingPause: TimeInterval = 1.5

        public init() {}
    }

    public let mode: SwitchMode
    public let configuration: Configuration

    /// The display that has keyboard focus, as far as Glazer knows.
    public private(set) var keyboardDisplay: Display.ID?

    /// In automatic mode, the display the pointer has moved to whose keyboard focus is
    /// waiting for the user to start typing.
    public private(set) var pendingDisplay: Display.ID?

    private var facedDisplay: Display.ID?
    private var isHoldKeyDown = false
    private var lastKeystroke: TimeInterval = -.infinity

    public init(mode: SwitchMode, keyboardDisplay: Display.ID?, configuration: Configuration = Configuration()) {
        self.mode = mode
        self.keyboardDisplay = keyboardDisplay
        self.configuration = configuration
        facedDisplay = keyboardDisplay
    }

    /// Whether this policy needs to know about keystrokes and the hold key.
    public var needsKeyboard: Bool {
        mode != .immediate
    }

    /// The user now faces `display`.
    public mutating func userFaces(_ display: Display.ID) -> [Action] {
        facedDisplay = display

        switch mode {
        case .immediate:
            return focusBoth(on: display)
        case .holdKey:
            return isHoldKeyDown ? focusBoth(on: display) : []
        case .automatic:
            pendingDisplay = display == keyboardDisplay ? nil : display
            return [.movePointer(display)]
        }
    }

    /// A key was pressed. Returns the actions to take before the key is delivered.
    public mutating func keyPressed(at timestamp: TimeInterval) -> [Action] {
        defer { lastKeystroke = timestamp }

        guard mode == .automatic,
            let pendingDisplay,
            timestamp - lastKeystroke >= configuration.typingPause
        else { return [] }

        keyboardDisplay = pendingDisplay
        self.pendingDisplay = nil
        return [.moveKeyboardFocus(pendingDisplay)]
    }

    /// The hold key went down or up.
    public mutating func holdKeyChanged(isDown: Bool) -> [Action] {
        isHoldKeyDown = isDown
        guard mode == .holdKey, isDown, let facedDisplay, facedDisplay != keyboardDisplay else { return [] }
        return focusBoth(on: facedDisplay)
    }

    /// The user moved the pointer to `display` themselves. Glazer takes that as their
    /// choice, so nothing is left waiting to switch.
    public mutating func userMovedPointer(to display: Display.ID) {
        facedDisplay = display
        pendingDisplay = nil
    }

    private mutating func focusBoth(on display: Display.ID) -> [Action] {
        guard display != keyboardDisplay else { return [.movePointer(display)] }
        keyboardDisplay = display
        pendingDisplay = nil
        return [.movePointer(display), .moveKeyboardFocus(display)]
    }
}
