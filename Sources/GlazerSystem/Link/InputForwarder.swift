import AppKit
import CoreGraphics
import GlazerCore
import OSLog

/// Takes this Mac's keyboard and mouse while the user faces a linked Mac, and hands each
/// event over to be sent there instead of acting here.
///
/// An event tap sees every key, click, movement and scroll. While forwarding, it swallows
/// them, except Glazer's own on/off shortcut, and the pointer here is held still. When not
/// forwarding, it only notes when the user is typing or holding a button, so a switch can
/// wait. It needs Accessibility access.
@MainActor
public final class InputForwarder {
    /// Each event taken while forwarding.
    public var onEvent: ((InputEvent) -> Void)?

    public private(set) var isForwarding = false
    /// Whether the tap is installed and working.
    public var isRunning: Bool {
        tap != nil
    }

    /// The key code and modifiers of a shortcut that always acts here, never forwarded.
    public var localShortcut: (keyCode: UInt16, flags: CGEventFlags)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var keysDown: Set<Int64> = []
    private var buttonsDown = 0
    private var lastKey = Date.distantPast

    public init() {}

    /// Whether the user is typing or holding a key or button here: a switch between Macs
    /// should wait.
    public var isBusy: Bool {
        !keysDown.isEmpty || buttonsDown > 0 || Date().timeIntervalSince(lastKey) < 0.6
    }

    /// Installs the tap. Returns whether it worked, which needs Accessibility access.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown,
            .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let forwarder = Unmanaged<InputForwarder>.fromOpaque(refcon).takeUnretainedValue()
                    // The tap's run loop source is on the main run loop.
                    nonisolated(unsafe) let event = event
                    let passes = MainActor.assumeIsolated { forwarder.passes(type, event) }
                    return passes ? Unmanaged.passUnretained(event) : nil
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Logger.link.error("Couldn't watch the keyboard and mouse: is Accessibility allowed?")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        setForwarding(false)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        keysDown.removeAll()
        buttonsDown = 0
    }

    /// Starts or stops forwarding. While forwarding, the pointer here stays still.
    public func setForwarding(_ forwarding: Bool) {
        guard forwarding != isForwarding else { return }
        isForwarding = forwarding
        CGAssociateMouseAndMouseCursorPosition(forwarding ? 0 : 1)
    }

    /// Whether `event` acts here; if not, it's been forwarded.
    private func passes(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS turns a slow tap off; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        // Events replayed from another Mac act here and go no further.
        if event.getIntegerValueField(.eventSourceUserData) == InputReplayer.marker {
            return true
        }
        note(type, event)
        guard isForwarding, let input = Self.input(from: type, event) else { return true }
        if case .key(let code, _, _, _) = input, let localShortcut, code == localShortcut.keyCode,
            event.flags.intersection(Self.modifiers) == localShortcut.flags
        {
            return true
        }
        onEvent?(input)
        return false
    }

    private static let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    private func note(_ type: CGEventType, _ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .keyDown:
            keysDown.insert(code)
            lastKey = Date()
        case .keyUp:
            keysDown.remove(code)
            lastKey = Date()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buttonsDown += 1
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            buttonsDown = max(buttonsDown - 1, 0)
        default:
            break
        }
    }

    /// `event` as an ``InputEvent``, or `nil` for kinds that aren't sent.
    static func input(from type: CGEventType, _ event: CGEvent) -> InputEvent? {
        let flags = event.flags.rawValue
        switch type {
        case .keyDown, .keyUp:
            return .key(
                code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), isDown: type == .keyDown,
                flags: flags, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            return .modifiers(code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: flags)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .move(
                dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY),
                flags: flags)
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
            let button =
                switch type {
                case .leftMouseDown, .leftMouseUp: 0
                case .rightMouseDown, .rightMouseUp: 1
                default: Int(event.getIntegerValueField(.mouseEventButtonNumber))
                }
            return .button(
                button, isDown: isDown, clicks: Int(event.getIntegerValueField(.mouseEventClickState)), flags: flags)
        case .scrollWheel:
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let dy =
                isContinuous
                ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let dx =
                isContinuous
                ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            return .scroll(
                dx: dx, dy: dy, isContinuous: isContinuous,
                phase: UInt32(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                momentum: UInt32(event.getIntegerValueField(.scrollWheelEventMomentumPhase)))
        default:
            return nil
        }
    }
}
