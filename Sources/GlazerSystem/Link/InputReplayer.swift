import AppKit
import CoreGraphics
import GlazerCore

/// Replays keyboard and mouse events from a linked Mac on this one.
///
/// Every event it posts carries ``marker``, so this Mac's own forwarder lets it act here
/// and never sends it back. It remembers what's held, so ``releaseAll()`` can let go of
/// everything when the other Mac stops, and nothing sticks.
@MainActor
public final class InputReplayer {
    /// Marks events Glazer replayed: "GLZR".
    public static let marker: Int64 = 0x474C_5A52

    public private(set) var held = HeldInput()
    private let source = CGEventSource(stateID: .combinedSessionState)

    public init() {}

    public func replay(_ input: InputEvent) {
        held.record(input)
        guard let event = Self.event(for: input, at: Self.pointer, buttons: held.buttons, source: source) else {
            return
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    /// Releases every key and button held by replayed events.
    public func releaseAll() {
        for release in held.releases() {
            replay(release)
        }
        held = HeldInput()
    }

    private static var pointer: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The Core Graphics event for `input`, with the pointer now at `pointer`.
    static func event(for input: InputEvent, at pointer: CGPoint, buttons: Set<Int>, source: CGEventSource?) -> CGEvent?
    {
        switch input {
        case .key(let code, let isDown, let flags, let isRepeat):
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = CGEventFlags(rawValue: flags)
            event?.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
            return event

        case .modifiers(let code, let flags):
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            event?.type = .flagsChanged
            event?.flags = CGEventFlags(rawValue: flags)
            return event

        case .move(let dx, let dy, let flags):
            let target = clamp(CGPoint(x: pointer.x + dx, y: pointer.y + dy))
            let type: CGEventType =
                buttons.contains(0)
                ? .leftMouseDragged
                : buttons.contains(1)
                    ? .rightMouseDragged
                    : buttons.isEmpty ? .mouseMoved : .otherMouseDragged
            let button: CGMouseButton = buttons.contains(1) ? .right : buttons.contains(0) ? .left : .center
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button)
            event?.setDoubleValueField(.mouseEventDeltaX, value: dx)
            event?.setDoubleValueField(.mouseEventDeltaY, value: dy)
            event?.flags = CGEventFlags(rawValue: flags)
            return event

        case .button(let number, let isDown, let clicks, let flags):
            let (type, button): (CGEventType, CGMouseButton) =
                switch number {
                case 0: (isDown ? .leftMouseDown : .leftMouseUp, .left)
                case 1: (isDown ? .rightMouseDown : .rightMouseUp, .right)
                default: (isDown ? .otherMouseDown : .otherMouseUp, .center)
                }
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: pointer, mouseButton: button)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(max(clicks, 1)))
            event?.flags = CGEventFlags(rawValue: flags)
            return event

        case .scroll(let dx, let dy, let isContinuous, let phase, let momentum):
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: isContinuous ? .pixel : .line, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: isContinuous ? 1 : 0)
            event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum))
            if isContinuous {
                event?.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
                event?.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            }
            return event
        }
    }

    /// `point` kept on a display, so the pointer can't be pushed off every screen.
    static func clamp(_ point: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let bounds = ids.map(CGDisplayBounds)
        if bounds.contains(where: { $0.contains(point) }) { return point }
        // Onto the nearest display's edge.
        let nearest = bounds.min { $0.distanceTo(point) < $1.distanceTo(point) }
        guard let nearest else { return point }
        return CGPoint(
            x: min(max(point.x, nearest.minX), nearest.maxX - 1), y: min(max(point.y, nearest.minY), nearest.maxY - 1))
    }
}

extension CGRect {
    fileprivate func distanceTo(_ point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
