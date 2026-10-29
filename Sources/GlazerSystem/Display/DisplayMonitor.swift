import AppKit
import GlazerCore
import Observation

/// Publishes the connected displays and the display that holds the pointer.
///
/// Display changes come from the system notification. The pointer has no change
/// notification that works across apps, so it is sampled a few times a second, and only
/// while someone is watching (see ``start()`` and ``stop()``).
@MainActor
@Observable
public final class DisplayMonitor {
    public private(set) var displays: [Display] = []
    public private(set) var pointerDisplayID: Display.ID?

    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var pointerTimer: Timer?

    public init() {
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
    }

    /// Starts following the pointer. Call when the display map becomes visible.
    public func start() {
        guard pointerTimer == nil else { return }
        refreshPointer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    /// Stops following the pointer.
    public func stop() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.compactMap(Display.init)
        refreshPointer()
    }

    private func refreshPointer() {
        let id = displays.display(containing: NSEvent.mouseLocation)?.id
        if id != pointerDisplayID {
            pointerDisplayID = id
        }
    }
}

extension Display {
    @MainActor
    init?(screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        self.init(id: number.uint32Value, name: screen.localizedName, frame: screen.frame)
    }
}
