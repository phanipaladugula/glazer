import ApplicationServices
import Foundation

/// Whether Glazer may use the Accessibility API, which it needs to bring a window on
/// another display to the front.
public enum AccessibilityAccess {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads to System Settings › Privacy & Security ›
    /// Accessibility. macOS shows it only once per app; after that, use
    /// ``SystemSettings/open(_:)``.
    public static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
