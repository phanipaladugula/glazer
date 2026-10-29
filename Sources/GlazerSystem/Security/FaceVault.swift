import Foundation
import GlazerCore
import Security

/// Keeps the face lock template in the macOS Keychain.
///
/// The template is biometric data, so it never goes in user defaults or a file. It's a
/// generic password item in the user's login keychain, which macOS encrypts with their
/// login password and never syncs to iCloud.
///
/// macOS lets the app that saved the item read it without asking, and asks the user
/// before any other app does. It recognises "the same app" by code signature, so builds
/// signed with Glazer's signing identity (see Scripts/signing.sh) read it silently, while
/// ad hoc builds are asked once per build.
public struct FaceVault: Sendable {
    public enum Failure: Error, Equatable {
        case keychain(OSStatus)
        case unreadable
    }

    private let service: String
    private let account = "face-template"

    /// - Parameter service: The Keychain service name. Tests use their own.
    public init(service: String = "io.github.phanipaladugula.glazer.face-lock") {
        self.service = service
    }

    /// Whether a template is stored, without reading it.
    public var hasTemplate: Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// The stored template, or `nil` if there isn't one.
    public func load() throws -> FaceTemplate? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let template = try? JSONDecoder().decode(FaceTemplate.self, from: data)
            else { throw Failure.unreadable }
            return template
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    /// Stores `template`, replacing any previous one. The old template is replaced in
    /// place, so a failed save never leaves the user with none.
    public func save(_ template: FaceTemplate) throws {
        let data = try JSONEncoder().encode(template)

        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw Failure.keychain(update)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Glazer face lock"
        item[kSecAttrDescription as String] = "Face signature used by Glazer to recognise you"

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    /// Deletes the stored template. Deleting when there is none is not an error.
    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
