import AppKit

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

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
