/// A key combination, described independently of any UI or hot key API.
public struct KeyboardShortcut: Equatable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The character on the key, uppercase for letters, such as "G".
    public let key: Character
    public let modifiers: Modifiers

    public init(key: Character, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The shortcut that turns Glazer on and off.
    public static let toggle = KeyboardShortcut(key: "G", modifiers: [.option, .command])

    /// The shortcut as macOS writes it in menus, such as "⌥⌘G".
    ///
    /// Modifiers follow Apple's order: Control, Option, Shift, Command.
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + String(key)
    }
}
