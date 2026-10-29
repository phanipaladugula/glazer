import AVFoundation
import AppKit

/// Reports whether someone is at the Mac: the screen is awake and unlocked, and this user's
/// session is the active one. Glazer turns the camera off whenever they aren't.
///
/// It also reports when a camera is connected, so Glazer can retry a camera that failed.
@MainActor
public final class SessionMonitor {
    /// Whether the screen is awake and unlocked, and this session is in front.
    public private(set) var isActive = true

    private var isLocked = false
    private var isAsleep = false
    private var isSwitchedOut = false
    // Written only during init, on the main actor; read in deinit.
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let onChange: @MainActor () -> Void

    /// - Parameter onChange: Called when ``isActive`` changes, and when a camera is
    ///   connected.
    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSwitchedOut = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSwitchedOut = false }

        // The screen lock has no public notification constant; these names are what macOS
        // posts on the distributed center, and are widely relied on.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isLocked = false }

        observe(NotificationCenter.default, AVCaptureDevice.wasConnectedNotification) { _ in }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, update: @escaping @MainActor (SessionMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.isActive = !(self.isLocked || self.isAsleep || self.isSwitchedOut)
                self.onChange()
            }
        }
        observers.append((center, token))
    }

    // Not an isolated deinit: Swift 6.3 crashes compiling those with code coverage on.
    deinit {
        for (center, token) in observers {
            center.removeObserver(token)
        }
    }
}
