import Carbon.HIToolbox
import GlazerCore

/// A system-wide keyboard shortcut.
///
/// Uses the Carbon hot key API, which works while other apps are active and needs no
/// Accessibility permission. The shortcut is unregistered when the object is released.
@MainActor
public final class HotKey {
    public enum Error: Swift.Error, Equatable {
        case unsupportedKey(Character)
        /// macOS itself uses the shortcut, such as for Spotlight or Mission Control.
        case reservedBySystem
        /// Another app has already registered the shortcut.
        case takenByAnotherApp
        case registrationFailed(OSStatus)
    }

    private static let signature: OSType = 0x474C_5A52  // "GLZR"
    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?

    private let id: UInt32
    nonisolated(unsafe) private var reference: EventHotKeyRef?

    /// Registers `shortcut` and calls `action` on the main thread each time it is pressed.
    ///
    /// - Parameter exclusive: Fail with ``Error/reservedBySystem`` or
    ///   ``Error/takenByAnotherApp`` rather than share the shortcut with macOS or another
    ///   app, where one press would do two things.
    public init(_ shortcut: KeyboardShortcut, exclusive: Bool = false, action: @escaping () -> Void) throws {
        guard let keyCode = KeyCodes.code(for: shortcut.key) else {
            throw Error.unsupportedKey(shortcut.key)
        }
        if exclusive, Self.isReservedBySystem(keyCode: keyCode, modifiers: shortcut.modifiers) {
            throw Error.reservedBySystem
        }
        try Self.installEventHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            exclusive ? OptionBits(kEventHotKeyExclusive) : 0,
            &reference
        )
        guard status != eventHotKeyExistsErr else { throw Error.takenByAnotherApp }
        guard status == noErr else { throw Error.registrationFailed(status) }
        Self.handlers[id] = action
    }

    // Not an isolated deinit: Swift 6.3 crashes compiling those with code coverage on.
    // Glazer creates and releases hot keys on the main thread, and the reference is only
    // touched here and in init.
    deinit {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        let id = id
        Task { @MainActor in HotKey.handlers[id] = nil }
    }

    private static func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated {
                    HotKey.handlers[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard status == noErr else { throw Error.registrationFailed(status) }
    }

    private static func carbonModifiers(for modifiers: KeyboardShortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    /// Whether one of macOS's own shortcuts that is switched on, such as Spotlight's or
    /// Mission Control's, uses this key and these modifiers.
    static func isReservedBySystem(keyCode: UInt32, modifiers: KeyboardShortcut.Modifiers) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
            let hotKeys = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        let wanted = carbonModifiers(for: modifiers)
        // Symbolic hot keys can carry extra flags, such as for the function key; only the
        // four modifiers a shortcut can have are compared.
        let mask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return hotKeys.contains { hotKey in
            guard hotKey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let code = hotKey[kHISymbolicHotKeyCode] as? Int,
                let flags = hotKey[kHISymbolicHotKeyModifiers] as? Int
            else { return false }
            return UInt32(code) == keyCode && UInt32(flags) & mask == wanted
        }
    }
}
