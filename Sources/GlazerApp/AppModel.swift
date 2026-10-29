import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// The app's state, shared by the menu bar icon and the panel.
@MainActor
@Observable
final class AppModel {
    /// Whether Glazer is on. Persists between launches.
    var isEnabled: Bool {
        didSet { preferences.isEnabled = isEnabled }
    }

    let displayMonitor = DisplayMonitor()
    let toggleShortcut = KeyboardShortcut.toggle

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var toggleHotKey: HotKey?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        isEnabled = preferences.isEnabled
        registerToggleShortcut()
    }

    func toggle() {
        isEnabled.toggle()
    }

    private func registerToggleShortcut() {
        do {
            toggleHotKey = try HotKey(toggleShortcut) { [weak self] in
                self?.toggle()
            }
        } catch {
            // Another app may own the shortcut. Glazer still works from the menu bar.
            Logger.app.error("Could not register \(self.toggleShortcut.displayString): \(error)")
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "app")
}
