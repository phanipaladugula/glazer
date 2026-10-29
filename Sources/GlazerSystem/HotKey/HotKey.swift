import Carbon.HIToolbox
import GlazerCore

/// A system-wide keyboard shortcut.
///
/// Uses the Carbon hot key API, which works while other apps are active and needs no
/// Accessibility permission. The shortcut is unregistered when the object is released.
@MainActor
public final class HotKey {
    public enum Error: Swift.Error {
        case unsupportedKey(Character)
        case registrationFailed(OSStatus)
    }

    private static let signature: OSType = 0x474C_5A52  // "GLZR"
    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?

    private let id: UInt32
    nonisolated(unsafe) private var reference: EventHotKeyRef?

    /// Registers `shortcut` and calls `action` on the main thread each time it is pressed.
    public init(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) throws {
        guard let keyCode = Self.keyCode(for: shortcut.key) else {
            throw Error.unsupportedKey(shortcut.key)
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
            0,
            &reference
        )
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

    /// Virtual key codes for the ANSI letter keys. These are physical positions, so on
    /// other keyboard layouts the shortcut stays on the same key.
    private static func keyCode(for key: Character) -> UInt32? {
        let codes: [Character: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
            "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
            "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
            "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        ]
        return codes[key].map(UInt32.init)
    }
}
