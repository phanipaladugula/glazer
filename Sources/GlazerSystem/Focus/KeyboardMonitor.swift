import CoreGraphics
import Foundation
import OSLog

/// Tells Glazer when the user types and when they hold Fn, so keyboard focus can follow
/// them at the right moment.
///
/// It sees every key event, because that is how macOS event taps work, but it reads only
/// two things: that a key went down, with its time, and whether Fn is held. It never reads
/// which key was pressed or what was typed, and stores nothing.
///
/// When moving keyboard focus on a keystroke, the key must reach the new window rather
/// than the old one. So the handler can ask for a key to be held: the monitor holds it,
/// and any keys that follow, for a moment while focus moves, then delivers them in order.
///
/// It needs Accessibility access. Without it, ``start()`` returns `false`.
@MainActor
public final class KeyboardMonitor {
    public enum Disposition: Sendable {
        /// Deliver the key now.
        case deliver
        /// Hold the key while keyboard focus moves, then deliver it.
        case holdForFocusChange
    }

    /// Called for each key press, with a monotonic timestamp in seconds.
    public var onKeyDown: ((TimeInterval) -> Disposition)?

    /// Called when Fn goes down or up.
    public var onHoldKeyChange: ((Bool) -> Void)?

    /// How long keys are held while focus moves. Long enough for the new window to become
    /// key, short enough that nobody notices.
    public var focusChangeDelay: TimeInterval = 0.06

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var heldEvents: [CGEvent] = []
    private var isHolding = false
    private var isFnDown = false

    /// Marks events Glazer re-posts, so the tap lets them through untouched.
    private static let replayMarker: Int64 = 0x474C_5A52  // "GLZR"

    public init() {}

    public var isRunning: Bool {
        tap != nil
    }

    /// Starts watching the keyboard. Returns `false` if macOS refused, which happens when
    /// Glazer doesn't have Accessibility access.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
                    // The tap's run loop source is on the main run loop, so this callback
                    // runs on the main thread and the event never leaves it.
                    nonisolated(unsafe) let event = event
                    nonisolated(unsafe) var result: Unmanaged<CGEvent>?
                    MainActor.assumeIsolated {
                        result = monitor.handle(type, event)
                    }
                    return result
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            Logger.keyboard.notice("Keyboard monitor unavailable: no Accessibility access")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    public func stop() {
        flushHeldEvents()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isFnDown = false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off if it's ever slow. Turn it back on.
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let fnDown = event.flags.contains(.maskSecondaryFn)
            if fnDown != isFnDown {
                isFnDown = fnDown
                onHoldKeyChange?(fnDown)
            }
            return Unmanaged.passUnretained(event)
        }

        if isHolding {
            hold(event)
            return nil
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard type == .keyDown, !isRepeat, onKeyDown?(ProcessInfo.processInfo.systemUptime) == .holdForFocusChange
        else { return Unmanaged.passUnretained(event) }

        isHolding = true
        hold(event)
        DispatchQueue.main.asyncAfter(deadline: .now() + focusChangeDelay) { [weak self] in
            self?.flushHeldEvents()
        }
        return nil
    }

    private func hold(_ event: CGEvent) {
        if let copy = event.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            heldEvents.append(copy)
        }
    }

    private func flushHeldEvents() {
        let events = heldEvents
        heldEvents.removeAll()
        isHolding = false
        for event in events {
            event.post(tap: .cgSessionEventTap)
        }
    }
}

extension Logger {
    static let keyboard = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "keyboard")
}
