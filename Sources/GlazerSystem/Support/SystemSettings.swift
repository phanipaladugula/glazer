import AppKit

/// Opens panes of System Settings, for permissions only the user can change there.
public enum SystemSettings {
    public enum Pane: String, Sendable {
        case camera = "Privacy_Camera"
        case accessibility = "Privacy_Accessibility"
        case loginItems = "LoginItems"
    }

    @MainActor
    public static func open(_ pane: Pane) {
        let address =
            switch pane {
            case .camera, .accessibility:
                "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
            case .loginItems:
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            }
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }
}
