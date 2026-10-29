import AppKit
import Carbon.HIToolbox

/// Reports when the user presses a key in any app, so Glazer doesn't switch displays while
/// they're typing.
///
/// It only observes: it can't block, delay or change a keystroke. From each key press it
/// reads the time, and nothing else: not which key, not what was typed. It stores nothing.
///
/// macOS delivers other apps' key events only with Accessibility access. Without it the
/// monitor sees no typing, and Glazer switches displays without waiting for a pause.
@MainActor
public final class TypingMonitor {
    private var monitor: Any?

    public init() {}

    /// Calls `onKeyPress` with a monotonic timestamp, in seconds, for each key press.
    public func start(onKeyPress: @escaping @MainActor (TimeInterval) -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
            let timestamp = ProcessInfo.processInfo.systemUptime
            MainActor.assumeIsolated { onKeyPress(timestamp) }
        }
    }

    /// The process that has Secure Event Input on, or `nil` if none has.
    ///
    /// While a password field has focus, macOS turns Secure Event Input on and hides
    /// keystrokes from other apps, so the monitor sees no typing. Glazer must not take that
    /// as a pause, or the rest of a password could go to another window. Some apps also
    /// leave it on for long stretches, such as Terminal's Secure Keyboard Entry, so callers
    /// should check which app holds it. Returns 0 when it's on but the holder is unknown.
    public var secureInputOwner: pid_t? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value ?? 0
    }

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
