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
}
