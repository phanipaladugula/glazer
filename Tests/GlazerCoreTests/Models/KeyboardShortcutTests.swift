import Testing

@testable import GlazerCore

@Suite("KeyboardShortcut")
struct KeyboardShortcutTests {
    @Test("The toggle shortcut reads ⌥⌘G")
    func toggle() {
        #expect(KeyboardShortcut.toggle.displayString == "⌥⌘G")
    }

    @Test("Modifiers follow Apple's order regardless of how they are given")
    func order() {
        let shortcut = KeyboardShortcut(key: "K", modifiers: [.command, .shift, .control, .option])
        #expect(shortcut.displayString == "⌃⌥⇧⌘K")
    }
}
