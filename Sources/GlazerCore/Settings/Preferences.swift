import Foundation

/// A place to read and write simple values. `UserDefaults` conforms; tests use an
/// in-memory store.
public protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// Settings that persist between launches.
///
/// Only settings live here. The face template is biometric data and lives in the
/// Keychain instead; see `FaceVault` in GlazerSystem.
public final class Preferences {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let switchDelay = "switchDelay"
        static let calibration = "calibration"
        static let switchingMethod = "switchingMethod"
        static let switchShortcut = "switchShortcut"
        static let gesturesEnabled = "gesturesEnabled"
        static let handCalibration = "handCalibration"
        static let handAim = "handAim"
        static let linkingEnabled = "linkingEnabled"
        static let linkDeviceID = "linkDeviceID"
        static let forwardsInput = "forwardsInput"
        static let acceptsInput = "acceptsInput"
        static let sharesClipboard = "sharesClipboard"
    }

    /// The range offered for ``switchDelay``, in seconds.
    public static let switchDelayRange: ClosedRange<Double> = 0.2...1.5

    private let store: KeyValueStore

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// Whether Glazer is on. Defaults to `true` so a first launch shows it working.
    public var isEnabled: Bool {
        get { store.object(forKey: Key.isEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.isEnabled) }
    }

    /// Whether the user has been through setup: permissions and calibration.
    public var hasCompletedSetup: Bool {
        get { store.object(forKey: Key.hasCompletedSetup) as? Bool ?? false }
        set { store.set(newValue, forKey: Key.hasCompletedSetup) }
    }

    /// How long the user must face another display before focus moves, in seconds.
    public var switchDelay: Double {
        get {
            let value = store.object(forKey: Key.switchDelay) as? Double ?? 0.5
            return min(max(value, Self.switchDelayRange.lowerBound), Self.switchDelayRange.upperBound)
        }
        set { store.set(newValue, forKey: Key.switchDelay) }
    }

    /// The saved calibration. Head angles only: no images and nothing that identifies the
    /// user.
    public var calibration: Calibration? {
        get {
            guard let data = store.object(forKey: Key.calibration) as? Data else { return nil }
            return try? JSONDecoder().decode(Calibration.self, from: data)
        }
        set {
            store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.calibration)
        }
    }

    /// How the user moves between displays. Defaults to following their head.
    public var switchingMethod: SwitchingMethod {
        get {
            (store.object(forKey: Key.switchingMethod) as? String).flatMap(SwitchingMethod.init(storedValue:))
                ?? .camera
        }
        set { store.set(newValue.rawValue, forKey: Key.switchingMethod) }
    }

    /// The shortcut that moves to the next display. Defaults to
    /// ``KeyboardShortcut/nextDisplay``, and to it again if the stored one can't be used.
    public var switchShortcut: KeyboardShortcut {
        get {
            guard let data = store.object(forKey: Key.switchShortcut) as? Data,
                let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
                shortcut.problemAsSwitchShortcut == nil
            else { return .nextDisplay }
            return shortcut
        }
        set { store.set(try? JSONEncoder().encode(newValue), forKey: Key.switchShortcut) }
    }

    /// Whether hand gestures take and drop screenshots. Off until the user turns it on,
    /// because it needs Screen Recording permission.
    public var gesturesEnabled: Bool {
        get { store.object(forKey: Key.gesturesEnabled) as? Bool ?? false }
        set { store.set(newValue, forKey: Key.gesturesEnabled) }
    }

    /// The user's open hand and fist, as the camera sees them. Measurements only: no
    /// images.
    public var handCalibration: HandCalibration? {
        get {
            guard let data = store.object(forKey: Key.handCalibration) as? Data else { return nil }
            return try? JSONDecoder().decode(HandCalibration.self, from: data)
        }
        set {
            store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.handCalibration)
        }
    }

    /// Where the user holds their hand for each display, when calibration could tell the
    /// displays apart that way.
    public var handAim: HandAim? {
        get {
            guard let data = store.object(forKey: Key.handAim) as? Data else { return nil }
            return try? JSONDecoder().decode(HandAim.self, from: data)
        }
        set {
            store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.handAim)
        }
    }

    // MARK: Linked Macs

    /// Whether this Mac links with other Macs on the local network. Off until the user
    /// turns it on.
    public var linkingEnabled: Bool {
        get { store.object(forKey: Key.linkingEnabled) as? Bool ?? false }
        set { store.set(newValue, forKey: Key.linkingEnabled) }
    }

    /// This Mac's ID among linked Macs: random, made the first time it's needed.
    public var linkDeviceID: String {
        if let id = store.object(forKey: Key.linkDeviceID) as? String, !id.isEmpty {
            return id
        }
        let id = UUID().uuidString
        store.set(id, forKey: Key.linkDeviceID)
        return id
    }

    /// Whether this Mac's keyboard and mouse control a linked Mac the user faces.
    public var forwardsInput: Bool {
        get { store.object(forKey: Key.forwardsInput) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.forwardsInput) }
    }

    /// Whether linked Macs' keyboards and mice may control this Mac.
    public var acceptsInput: Bool {
        get { store.object(forKey: Key.acceptsInput) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.acceptsInput) }
    }

    /// Whether the clipboard moves with the keyboard and mouse between linked Macs.
    public var sharesClipboard: Bool {
        get { store.object(forKey: Key.sharesClipboard) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.sharesClipboard) }
    }
}
