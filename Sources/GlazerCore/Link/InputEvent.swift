import Foundation

/// A keyboard or mouse event, in a form one Mac can send another to replay.
///
/// Keys go by key code, a physical position, so the replaying Mac's keyboard layout
/// decides what's typed, as with Universal Control. The pointer goes by how far it moved,
/// not where it is, because the Macs' screens differ.
public enum InputEvent: Codable, Equatable, Sendable {
    /// A key went down or up. `flags` are the modifier flags at the time, as Core
    /// Graphics reports them.
    case key(code: UInt16, isDown: Bool, flags: UInt64, isRepeat: Bool)
    /// A modifier key, such as ⇧, went down or up; `flags` say which are now down.
    case modifiers(code: UInt16, flags: UInt64)
    /// The pointer moved by (`dx`, `dy`) points.
    case move(dx: Double, dy: Double, flags: UInt64)
    /// A mouse button went down or up. 0 is the left button, 1 the right.
    case button(Int, isDown: Bool, clicks: Int, flags: UInt64)
    /// A scroll by (`dx`, `dy`): pixels for a trackpad, lines for a wheel.
    case scroll(dx: Double, dy: Double, isContinuous: Bool, phase: UInt32, momentum: UInt32)
}

/// Which keys and buttons a stream of ``InputEvent``s is holding down, so they can all be
/// released when the stream stops, and nothing sticks.
public struct HeldInput: Equatable, Sendable {
    public private(set) var keys: Set<UInt16> = []
    public private(set) var buttons: Set<Int> = []
    public private(set) var flags: UInt64 = 0

    public init() {}

    public var isEmpty: Bool {
        keys.isEmpty && buttons.isEmpty && flags & Self.modifierMask == 0
    }

    /// The modifier flag bits Core Graphics uses for ⇪, ⇧, ⌃, ⌥, ⌘ and fn.
    public static let modifierMask: UInt64 = 0x00FF_0000

    public mutating func record(_ event: InputEvent) {
        switch event {
        case .key(let code, let isDown, let flags, _):
            if isDown { keys.insert(code) } else { keys.remove(code) }
            self.flags = flags
        case .modifiers(_, let flags):
            self.flags = flags
        case .button(let button, let isDown, _, _):
            if isDown { buttons.insert(button) } else { buttons.remove(button) }
        case .move, .scroll:
            break
        }
    }

    /// Events that release everything held: buttons, then keys, then modifiers.
    public func releases() -> [InputEvent] {
        let cleared = flags & ~Self.modifierMask
        var events = buttons.sorted().map { InputEvent.button($0, isDown: false, clicks: 1, flags: cleared) }
        events += keys.sorted().map { InputEvent.key(code: $0, isDown: false, flags: cleared, isRepeat: false) }
        if flags & Self.modifierMask != 0 {
            events.append(.modifiers(code: 0, flags: cleared))
        }
        return events
    }
}
