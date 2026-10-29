import GlazerCore

/// How each ``SwitchingMethod`` is named and described in Setup and Settings.
extension SwitchingMethod {
    var title: String {
        switch self {
        case .camera: "Where I look"
        case .shortcut: "A keyboard shortcut"
        case .both: "Both"
        }
    }

    var detail: String {
        switch self {
        case .camera:
            "The camera sees which display you turn to."
        case .shortcut:
            "Press a shortcut to jump. The camera stays off."
        case .both:
            "Follows where you look, and the shortcut jumps."
        }
    }

    var symbol: String {
        switch self {
        case .camera: "eye"
        case .shortcut: "keyboard"
        case .both: "eye.circle"
        }
    }
}
