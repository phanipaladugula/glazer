import Testing

@testable import GlazerCore

@Suite("Preferences")
struct PreferencesTests {
    final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]

        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

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
