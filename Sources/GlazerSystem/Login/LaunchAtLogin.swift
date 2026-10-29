import OSLog
import ServiceManagement

/// Starts Glazer when the user logs in, using the system's login items.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is waiting for the user to approve the login item in System Settings.
    public static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.login.error("Could not change launch at login: \(error)")
        }
    }
}

extension Logger {
    static let login = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "login")
}
