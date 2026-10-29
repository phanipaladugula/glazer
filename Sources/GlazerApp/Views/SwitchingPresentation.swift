import GlazerCore

/// How each ``SwitchingMethod`` is named and described in Setup and Settings.
extension SwitchingMethod {
    var title: String {
        switch self {
        case .camera: "Where I look"
        case .doublePress: "Double-pressing a key"
        case .both: "Both"
        }
    }

    var detail: String {
        switch self {
        case .camera:
            "The camera sees which display you turn to."
        case .doublePress:
            "Double-press a key to jump. The camera stays off."
        case .both:
            "Follows where you look, and a double-press jumps."
        }
    }

    var symbol: String {
        switch self {
        case .camera: "eye"
        case .doublePress: "keyboard"
        case .both: "eye.circle"
        }
    }
}

extension SwitchKey {
    /// A note about the key, when macOS may also use it.
    var caveat: String? {
        switch self {
        case .function:
            "If Dictation or the 🌐 key is set to start on a double-press of fn, choose another key, "
                + "or change that in System Settings › Keyboard."
        default:
            nil
        }
    }
}
