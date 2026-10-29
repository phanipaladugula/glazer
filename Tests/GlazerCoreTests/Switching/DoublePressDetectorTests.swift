import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("DoublePressDetector")
struct DoublePressDetectorTests {
    /// Feeds (event, time) pairs and returns the times at which a double-press fired.
    func fired(_ events: [(DoublePressDetector.Event, Double)]) -> [Double] {
        var detector = DoublePressDetector()
        return events.compactMap { event, time in detector.add(event, at: time) ? time : nil }
    }

    @Test("Two quick taps are a double-press, firing as the second is released")
    func doubleTap() {
        #expect(fired([(.keyDown, 0), (.keyUp, 0.08), (.keyDown, 0.25), (.keyUp, 0.32)]) == [0.32])
    }

    @Test("One tap is not")
    func singleTap() {
        #expect(fired([(.keyDown, 0), (.keyUp, 0.08)]).isEmpty)
    }

    @Test("Taps too far apart are two single taps")
    func slowTaps() {
        #expect(fired([(.keyDown, 0), (.keyUp, 0.08), (.keyDown, 0.9), (.keyUp, 0.98)]).isEmpty)
    }

    @Test("Holding the key, as a modifier, doesn't count")
    func held() {
        #expect(fired([(.keyDown, 0), (.keyUp, 0.08), (.keyDown, 0.2), (.keyUp, 1.2)]).isEmpty)
        #expect(fired([(.keyDown, 0), (.keyUp, 0.9), (.keyDown, 1.0), (.keyUp, 1.05)]).isEmpty)
    }

    @Test("Another key between the taps cancels it, as in fn and an arrow")
    func otherKeyBetween() {
        #expect(fired([(.keyDown, 0), (.keyUp, 0.08), (.otherKey, 0.15), (.keyDown, 0.2), (.keyUp, 0.28)]).isEmpty)
        #expect(fired([(.keyDown, 0), (.otherKey, 0.05), (.keyUp, 0.08), (.keyDown, 0.2), (.keyUp, 0.28)]).isEmpty)
    }

    @Test("A slow first tap followed by two quick ones still fires once")
    func recoversAfterMiss() {
        let events: [(DoublePressDetector.Event, Double)] = [
            (.keyDown, 0), (.keyUp, 0.1),
            (.keyDown, 1.0), (.keyUp, 1.1), (.keyDown, 1.3), (.keyUp, 1.38),
        ]
        #expect(fired(events) == [1.38])
    }

    @Test("Four quick taps are two double-presses, not three")
    func fourTaps() {
        let events: [(DoublePressDetector.Event, Double)] = [
            (.keyDown, 0), (.keyUp, 0.05), (.keyDown, 0.15), (.keyUp, 0.2),
            (.keyDown, 0.3), (.keyUp, 0.35), (.keyDown, 0.45), (.keyUp, 0.5),
        ]
        #expect(fired(events) == [0.2, 0.5])
    }

    @Test("A key-up without a key-down is ignored")
    func strayKeyUp() {
        #expect(fired([(.keyUp, 0), (.keyDown, 0.1), (.keyUp, 0.15)]).isEmpty)
    }
}

@Suite("Switching settings")
struct SwitchingSettingsTests {
    @Test("Each method says what it uses")
    func methods() {
        #expect(SwitchingMethod.camera.usesCamera && !SwitchingMethod.camera.usesKey)
        #expect(!SwitchingMethod.doublePress.usesCamera && SwitchingMethod.doublePress.usesKey)
        #expect(SwitchingMethod.both.usesCamera && SwitchingMethod.both.usesKey)
    }

    @Test("Every key has a name and a short name")
    func keyNames() {
        for key in SwitchKey.allCases {
            #expect(!key.name.isEmpty && !key.shortName.isEmpty)
        }
    }

    @Test("The camera and fn are the defaults, and choices persist")
    func preferences() {
        let store = MemoryStore()
        #expect(Preferences(store: store).switchingMethod == .camera)
        #expect(Preferences(store: store).switchKey == .function)

        Preferences(store: store).switchingMethod = .doublePress
        Preferences(store: store).switchKey = .rightOption
        #expect(Preferences(store: store).switchingMethod == .doublePress)
        #expect(Preferences(store: store).switchKey == .rightOption)
    }

    @Test("An unknown stored value falls back to the default")
    func unknownValue() {
        let store = MemoryStore()
        store.set("telepathy", forKey: "switchingMethod")
        #expect(Preferences(store: store).switchingMethod == .camera)
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
