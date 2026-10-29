@testable import GlazerCore

/// An in-memory `KeyValueStore`.
final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
