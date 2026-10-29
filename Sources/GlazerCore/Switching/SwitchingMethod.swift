/// How the user moves between displays.
public enum SwitchingMethod: String, CaseIterable, Sendable, Codable {
    /// Glazer follows which display the user's head faces, with the camera.
    case camera
    /// The user presses a keyboard shortcut to move to the next display. The camera
    /// stays off.
    case shortcut
    /// Both: Glazer follows the user's head, and the shortcut switches straight away.
    case both

    /// Reads a stored value. Glazer 0.2.0 stored "doublePress" for switching by key,
    /// which the shortcut replaced.
    public init?(storedValue: String) {
        if storedValue == "doublePress" {
            self = .shortcut
        } else {
            self.init(rawValue: storedValue)
        }
    }

    public var usesCamera: Bool {
        self != .shortcut
    }

    public var usesShortcut: Bool {
        self != .camera
    }
}
