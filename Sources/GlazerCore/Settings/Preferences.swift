import Foundation

/// A place to read and write simple values. `UserDefaults` conforms; tests use an
/// in-memory store.
public protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// Settings that persist between launches.
public final class Preferences {
    private enum Key {
        static let isEnabled = "isEnabled"
    }

    private let store: KeyValueStore

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// Whether Glazer is on. Defaults to `true` so a first launch shows it working.
    public var isEnabled: Bool {
        get { store.object(forKey: Key.isEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.isEnabled) }
    }
}
