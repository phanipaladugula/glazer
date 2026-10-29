import AppKit
import Carbon.HIToolbox
import GlazerCore

/// Watches for a double-press of one modifier key, in any app.
///
/// It reads only which modifier keys go up and down, and that some other key was pressed:
/// never which key, and never what's typed. It stores nothing. Like the typing monitor, it
/// sees other apps' keys only with Accessibility access.
@MainActor
public final class DoublePressMonitor {
    private var monitors: [Any] = []
    private var detector = DoublePressDetector()
    private var key: SwitchKey = .function

    public init() {}

    /// Calls `onDoublePress` each time `key` is double-pressed. Calling it again replaces
    /// the key and the handler.
    public func start(key: SwitchKey, onDoublePress: @escaping @MainActor () -> Void) {
        stop()
        self.key = key
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.handle(event) else { return }
                onDoublePress()
            }
        }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) {
            monitors.append(global)
        }
        // Global monitors don't see Glazer's own windows, such as Settings.
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { event in
                handle(event)
                return event
            })
        {
            monitors.append(local)
        }
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        detector.reset()
    }

    public var isRunning: Bool {
        !monitors.isEmpty
    }

    /// Feeds `event` to the detector, and returns whether it completed a double-press.
    private func handle(_ event: NSEvent) -> Bool {
        let timestamp = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .keyDown:
            return detector.add(.otherKey, at: timestamp)
        case .flagsChanged:
            guard Self.keyCodes(for: key).contains(Int(event.keyCode)) else {
                return detector.add(.otherKey, at: timestamp)
            }
            let isDown = Self.isDown(key, flags: event.modifierFlags)
            return detector.add(isDown ? .keyDown : .keyUp, at: timestamp)
        default:
            return false
        }
    }

    /// The virtual key codes that report `key`. The fn key reports kVK_Function, and the
    /// 🌐 key on some keyboards reports 179.
    static func keyCodes(for key: SwitchKey) -> Set<Int> {
        switch key {
        case .function: [kVK_Function, 179]
        case .rightOption: [kVK_RightOption]
        case .rightCommand: [kVK_RightCommand]
        case .rightControl: [kVK_RightControl]
        case .rightShift: [kVK_RightShift]
        }
    }

    /// Whether `key` is down, from an event's modifier flags. Right-hand modifiers are told
    /// apart from left-hand ones by their device-specific bits.
    static func isDown(_ key: SwitchKey, flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        switch key {
        case .function: return flags.contains(.function)
        case .rightOption: return raw & UInt(NX_DEVICERALTKEYMASK) != 0
        case .rightCommand: return raw & UInt(NX_DEVICERCMDKEYMASK) != 0
        case .rightControl: return raw & UInt(NX_DEVICERCTLKEYMASK) != 0
        case .rightShift: return raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0
        }
    }
}
