/// A key combination, described independently of any UI or hot key API.
public struct KeyboardShortcut: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Why a shortcut can't be used to switch displays.
    public enum Problem: Equatable, Sendable {
        /// It has fewer than two of Control, Option and Command, so it would take over
        /// shortcuts apps use every day, such as ⌘K, or typing, such as ⌥E.
        case needsMoreModifiers
        /// It's the shortcut that turns Glazer on and off.
        case sameAsToggle
    }

    /// The key: an uppercase letter or a digit, such as "G" or "1", an arrow ("←", "→",
    /// "↑", "↓"), or " " for Space. ``supportedKeys`` lists them all.
    public let key: Character
    public let modifiers: Modifiers

    public init(key: Character, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The keys a shortcut can use.
    public static let supportedKeys: [Character] =
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") + ["←", "→", "↑", "↓", " "]

    /// The shortcut that turns Glazer on and off.
    public static let toggle = KeyboardShortcut(key: "G", modifiers: [.option, .command])

    /// The default shortcut that moves to the next display. macOS doesn't use it, and
    /// common window managers don't either.
    public static let nextDisplay = KeyboardShortcut(key: " ", modifiers: [.control, .option, .command])

    /// The key's name as macOS writes it in menus, such as "G", "→" or "Space".
    public var keyName: String {
        key == " " ? "Space" : String(key)
    }

    /// The shortcut as macOS writes it in menus, such as "⌥⌘G".
    ///
    /// Modifiers follow Apple's order: Control, Option, Shift, Command.
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    /// Why this shortcut can't switch displays, or `nil` if it can. Whether macOS or
    /// another app already uses it is checked when it's registered.
    public var problemAsSwitchShortcut: Problem? {
        let strong: [Modifiers] = [.control, .option, .command]
        guard strong.filter(modifiers.contains).count >= 2 else { return .needsMoreModifiers }
        guard self != .toggle else { return .sameAsToggle }
        return nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case key, modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        guard key.count == 1, let character = key.first, Self.supportedKeys.contains(character) else {
            throw DecodingError.dataCorruptedError(
                forKey: .key, in: container, debugDescription: "Unsupported key \(key)")
        }
        self.key = character
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(key), forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
    }
}
