import Foundation
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

    @Test("Space and arrows have their menu names")
    func keyNames() {
        #expect(KeyboardShortcut.nextDisplay.displayString == "⌃⌥⌘Space")
        #expect(KeyboardShortcut(key: "→", modifiers: [.control, .option]).displayString == "⌃⌥→")
    }

    @Test("A switch shortcut needs two of Control, Option and Command")
    func modifiers() {
        #expect(KeyboardShortcut(key: "K", modifiers: [.command]).problemAsSwitchShortcut == .needsMoreModifiers)
        #expect(
            KeyboardShortcut(key: "K", modifiers: [.shift, .command]).problemAsSwitchShortcut == .needsMoreModifiers)
        #expect(KeyboardShortcut(key: "E", modifiers: [.option]).problemAsSwitchShortcut == .needsMoreModifiers)
        #expect(KeyboardShortcut(key: "K", modifiers: [.option, .command]).problemAsSwitchShortcut == nil)
        #expect(KeyboardShortcut.nextDisplay.problemAsSwitchShortcut == nil)
    }

    @Test("The toggle shortcut can't also switch displays")
    func notToggle() {
        #expect(KeyboardShortcut.toggle.problemAsSwitchShortcut == .sameAsToggle)
    }

    @Test("Every supported key survives a round trip; others don't decode")
    func codable() throws {
        for key in KeyboardShortcut.supportedKeys {
            let shortcut = KeyboardShortcut(key: key, modifiers: [.control, .shift])
            let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))
            #expect(decoded == shortcut)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyboardShortcut.self, from: Data("{\"key\":\"AB\",\"modifiers\":1}".utf8))
        }
    }
}
