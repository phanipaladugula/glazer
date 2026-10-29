import CoreGraphics
import Foundation
import Testing

@testable import GlazerCore

@Suite("Switching settings")
struct SwitchingSettingsTests {
    @Test("Each method says what it uses")
    func methods() {
        #expect(SwitchingMethod.camera.usesCamera && !SwitchingMethod.camera.usesShortcut)
        #expect(!SwitchingMethod.shortcut.usesCamera && SwitchingMethod.shortcut.usesShortcut)
        #expect(SwitchingMethod.both.usesCamera && SwitchingMethod.both.usesShortcut)
    }

    @Test("The camera and ⌃⌥⌘Space are the defaults, and choices persist")
    func preferences() {
        let store = MemoryStore()
        #expect(Preferences(store: store).switchingMethod == .camera)
        #expect(Preferences(store: store).switchShortcut == .nextDisplay)

        let shortcut = KeyboardShortcut(key: "→", modifiers: [.control, .command])
        Preferences(store: store).switchingMethod = .shortcut
        Preferences(store: store).switchShortcut = shortcut
        #expect(Preferences(store: store).switchingMethod == .shortcut)
        #expect(Preferences(store: store).switchShortcut == shortcut)
    }

    @Test("Switching by double-press, from Glazer 0.2.0, becomes switching by shortcut")
    func fromDoublePress() {
        let store = MemoryStore()
        store.set("doublePress", forKey: "switchingMethod")
        #expect(Preferences(store: store).switchingMethod == .shortcut)
    }

    @Test("An unknown stored value falls back to the default")
    func unknownValue() {
        let store = MemoryStore()
        store.set("telepathy", forKey: "switchingMethod")
        #expect(Preferences(store: store).switchingMethod == .camera)
    }

    @Test("A stored shortcut that can't be used, or can't be read, falls back to the default")
    func unusableShortcut() throws {
        let store = MemoryStore()
        store.set(try JSONEncoder().encode(KeyboardShortcut(key: "K", modifiers: [.command])), forKey: "switchShortcut")
        #expect(Preferences(store: store).switchShortcut == .nextDisplay)
        store.set(Data("{\"key\":\"é\",\"modifiers\":1}".utf8), forKey: "switchShortcut")
        #expect(Preferences(store: store).switchShortcut == .nextDisplay)
    }
}

@Suite("Display order")
struct DisplayOrderTests {
    let macBook = Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    let lgAbove = Display(id: 5, name: "LG", frame: CGRect(x: -177, y: 982, width: 1920, height: 1080))
    let lgRight = Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440))
    let third = Display(id: 3, name: "Third", frame: CGRect(x: 4072, y: 0, width: 1920, height: 1080))

    @Test("Stacked displays are ordered top to bottom")
    func stacked() {
        #expect([macBook, lgAbove].inReadingOrder.map(\.id) == [5, 1])
    }

    @Test("Side-by-side displays are ordered left to right, even at different heights")
    func sideBySide() {
        #expect([lgRight, macBook, third].inReadingOrder.map(\.id) == [1, 2, 3])
    }

    @Test("With two displays, the next one is the other one")
    func two() {
        #expect([macBook, lgAbove].display(after: 1)?.id == 5)
        #expect([macBook, lgAbove].display(after: 5)?.id == 1)
    }

    @Test("With three, it moves along and wraps round")
    func three() {
        let displays = [macBook, lgRight, third]
        #expect(displays.display(after: 1)?.id == 2)
        #expect(displays.display(after: 3)?.id == 1)
    }

    @Test("Unknown or no current display starts at the first; one display has nowhere to go")
    func edges() {
        #expect([macBook, lgAbove].display(after: nil)?.id == 5)
        #expect([macBook].display(after: 1) == nil)
    }
}
