import Foundation
import GlazerCore
import Security

/// The Macs this Mac is paired with, and the key shared with each, in the Keychain.
///
/// Each paired Mac is one generic password item in the login keychain: its ID as the
/// account, its name and key as the data. Like the face lock item, it never syncs to
/// iCloud, and only Glazer reads it without asking.
public struct PeerStore: Sendable {
    public enum Failure: Error, Equatable {
        case keychain(OSStatus)
    }

    public struct Peer: Codable, Equatable, Sendable {
        public let identity: PeerIdentity
        /// The 32-byte key from pairing.
        public let key: Data

        public init(identity: PeerIdentity, key: Data) {
            self.identity = identity
            self.key = key
        }
    }

    private let service: String

    /// - Parameter service: The Keychain service name. Tests use their own.
    public init(service: String = "io.github.phanipaladugula.glazer.linked-macs") {
        self.service = service
    }

    /// Every paired Mac, by name.
    public func peers() throws -> [Peer] {
        // The login keychain can't return the data of many items at once, so list the
        // accounts, then read each.
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw Failure.keychain(status)
        }
        let accounts = (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
        return try accounts.compactMap(peer)
            .sorted { $0.identity.name.localizedStandardCompare($1.identity.name) == .orderedAscending }
    }

    private func peer(_ id: String) throws -> Peer? {
        var query = baseQuery
        query[kSecAttrAccount as String] = id
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { try? JSONDecoder().decode(Peer.self, from: $0) }
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    /// Stores `peer`, replacing an earlier pairing with the same Mac.
    public func save(_ peer: Peer) throws {
        let data = try JSONEncoder().encode(peer)
        var match = baseQuery
        match[kSecAttrAccount as String] = peer.identity.id

        let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw Failure.keychain(update)
        }

        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Glazer linked Mac: \(peer.identity.name)"
        item[kSecAttrDescription as String] = "Key Glazer shares with a Mac it's paired with"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    /// Forgets the Mac with `id`. Forgetting one that isn't stored is not an error.
    public func remove(id: String) throws {
        var match = baseQuery
        match[kSecAttrAccount as String] = id
        let status = SecItemDelete(match as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    /// Forgets every paired Mac.
    public func removeAll() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
