import Testing

@testable import GlazerCore

@Suite("Preferences")
struct PreferencesTests {
    @Test("Glazer is on by default")
    func defaultIsOn() {
        #expect(Preferences(store: MemoryStore()).isEnabled)
    }

    @Test("The on/off state persists")
    func persists() {
        let store = MemoryStore()
        Preferences(store: store).isEnabled = false

        #expect(Preferences(store: store).isEnabled == false)
    }

    @Test("Setup starts incomplete")
    func setupIncomplete() {
        #expect(!Preferences(store: MemoryStore()).hasCompletedSetup)
    }

    @Test("The switch delay defaults to half a second")
    func defaultDelay() {
        #expect(Preferences(store: MemoryStore()).switchDelay == 0.5)
    }

    @Test("The switch delay is clamped to the offered range", arguments: [(0.0, 0.2), (9.0, 1.5), (0.8, 0.8)])
    func clampedDelay(stored: Double, expected: Double) {
        let store = MemoryStore()
        store.set(stored, forKey: "switchDelay")
        #expect(Preferences(store: store).switchDelay == expected)
    }

    @Test("A calibration survives a round trip, and can be cleared")
    func calibration() {
        let store = MemoryStore()
        Preferences(store: store).calibration = twoDisplayCalibration
        #expect(Preferences(store: store).calibration == twoDisplayCalibration)

        Preferences(store: store).calibration = nil
        #expect(Preferences(store: store).calibration == nil)
    }
}

@Suite("Preferences, writes")
struct PreferencesWriteTests {
    @Test("Setup state and switch delay persist")
    func persists() {
        let store = MemoryStore()
        let preferences = Preferences(store: store)
        preferences.hasCompletedSetup = true
        preferences.switchDelay = 0.9

        let reloaded = Preferences(store: store)
        #expect(reloaded.hasCompletedSetup)
        #expect(reloaded.switchDelay == 0.9)
    }
}

@Suite("Preferences, gestures")
struct GesturePreferencesTests {
    @Test("Gestures start off, with no hand calibration")
    func defaults() {
        let preferences = Preferences(store: MemoryStore())

        #expect(!preferences.gesturesEnabled)
        #expect(preferences.handCalibration == nil)
    }

    @Test("Gestures and the hand calibration persist")
    func persists() {
        let store = MemoryStore()
        let preferences = Preferences(store: store)
        preferences.gesturesEnabled = true
        preferences.handCalibration = Hands.calibration

        let reloaded = Preferences(store: store)
        #expect(reloaded.gesturesEnabled)
        #expect(reloaded.handCalibration == Hands.calibration)

        reloaded.handCalibration = nil
        #expect(Preferences(store: store).handCalibration == nil)
    }
}
