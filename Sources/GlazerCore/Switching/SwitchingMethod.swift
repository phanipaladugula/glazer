/// How the user moves between displays.
public enum SwitchingMethod: String, CaseIterable, Sendable, Codable {
    /// Glazer follows which display the user's head faces, with the camera.
    case camera
    /// The user double-presses a key to move to the next display. The camera stays off.
    case doublePress
    /// Both: Glazer follows the user's head, and a double-press switches straight away.
    case both

    public var usesCamera: Bool {
        self != .doublePress
    }

    public var usesKey: Bool {
        self != .camera
    }
}

/// A modifier key the user can double-press to switch displays.
///
/// Only keys that do nothing when tapped on their own are offered, so double-pressing one
/// never types anything. Right-hand modifiers are offered rather than left-hand ones, which
/// shortcuts use far more.
public enum SwitchKey: String, CaseIterable, Sendable, Codable {
    case function
    case rightOption
    case rightCommand
    case rightControl
    case rightShift

    /// The name shown in the app, such as "fn" or "Right ⌥ Option".
    public var name: String {
        switch self {
        case .function: "fn / 🌐"
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        case .rightShift: "Right ⇧ Shift"
        }
    }

    /// A short name for sentences, such as "fn" or "right ⌥".
    public var shortName: String {
        switch self {
        case .function: "fn"
        case .rightOption: "right ⌥"
        case .rightCommand: "right ⌘"
        case .rightControl: "right ⌃"
        case .rightShift: "right ⇧"
        }
    }
}
