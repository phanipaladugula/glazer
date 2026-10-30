import CryptoKit
import Foundation

/// One Mac as its linked Macs know it.
public struct PeerIdentity: Codable, Hashable, Sendable {
    /// A random ID made once per Mac. It identifies the Mac, not the person.
    public let id: String
    /// The Mac's name, such as "Phani's MacBook Pro", for showing to the user.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Pairs two Macs: a key exchange both users confirm by comparing a six-digit code.
///
/// ```
///   initiator                                   responder
///   commit(me, SHA256(myKey ‖ myNonce))   ──▶
///                                         ◀──   key(me, theirKey, theirNonce)
///   reveal(myKey, myNonce)                ──▶   checks the commitment
///   both show the code; the user confirms on each Mac
///   confirm(MAC)                          ◀─▶   confirm(MAC)
/// ```
///
/// The initiator commits to its key before it sees the responder's, so a machine in the
/// middle can't pick keys that make the two codes match: its only chance is guessing,
/// one in a million, while the user watches. See docs/adr/0010.
///
/// The session holds no network connection; the caller carries its messages.
public struct PairingSession: Sendable {
    public enum Role: Sendable {
        case initiator
        case responder
    }

    public enum Message: Codable, Equatable, Sendable {
        case commit(PeerIdentity, commitment: Data)
        case key(PeerIdentity, publicKey: Data, nonce: Data)
        case reveal(publicKey: Data, nonce: Data)
        case confirm(mac: Data)
        case decline
    }

    public enum Failure: Error, Equatable, Sendable {
        /// A message arrived out of order, or twice.
        case unexpectedMessage
        /// A key or nonce wasn't the right size, or the key wasn't a valid point.
        case badKey
        /// The initiator's revealed key didn't match what it committed to.
        case commitmentMismatch
        /// The other Mac's confirmation didn't match this exchange: the codes differed.
        case badConfirmation
        /// The user on the other Mac declined.
        case declined
    }

    /// The result: who was paired, and the key both Macs now share.
    public struct Pairing: Equatable, Sendable {
        public let peer: PeerIdentity
        /// 32 bytes, for the link's TLS pre-shared key.
        public let key: Data
    }

    public let role: Role
    public let me: PeerIdentity

    /// The other Mac, once known.
    public private(set) var peer: PeerIdentity?
    /// The code to show, once both keys are known.
    public private(set) var code: String?
    /// Set once both Macs have confirmed.
    public private(set) var pairing: Pairing?

    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = Self.randomBytes(16)
    private var commitment: Data?
    private var responderKey: Data?
    private var responderNonce: Data?
    private var keys: (confirm: SymmetricKey, link: Data, transcript: Data)?
    private var accepted = false
    private var peerConfirmed = false

    public init(role: Role, me: PeerIdentity) {
        self.role = role
        self.me = me
    }

    /// The first message, which the initiator sends.
    public mutating func start() -> Message {
        let commitment = Self.commit(publicKey: privateKey.publicKey.rawRepresentation, nonce: nonce)
        self.commitment = commitment
        return .commit(me, commitment: commitment)
    }

    /// Handles a message from the other Mac, and returns the reply to send, if any.
    public mutating func receive(_ message: Message) throws(Failure) -> Message? {
        switch (role, message) {
        case (_, .decline):
            throw .declined

        case (.responder, .commit(let identity, let commitment)):
            guard self.commitment == nil, commitment.count == SHA256.byteCount else { throw .unexpectedMessage }
            self.commitment = commitment
            peer = identity
            return .key(me, publicKey: privateKey.publicKey.rawRepresentation, nonce: nonce)

        case (.initiator, .key(let identity, let publicKey, let nonce)):
            guard let commitment, keys == nil else { throw .unexpectedMessage }
            peer = identity
            responderKey = publicKey
            responderNonce = nonce
            try derive(
                commitment: commitment, initiator: me, responder: identity,
                initiatorKey: privateKey.publicKey.rawRepresentation, initiatorNonce: self.nonce,
                responderKey: publicKey, responderNonce: nonce, theirKey: publicKey)
            return .reveal(publicKey: privateKey.publicKey.rawRepresentation, nonce: self.nonce)

        case (.responder, .reveal(let publicKey, let nonce)):
            guard let commitment, let peer, keys == nil else { throw .unexpectedMessage }
            guard Self.commit(publicKey: publicKey, nonce: nonce) == commitment else { throw .commitmentMismatch }
            try derive(
                commitment: commitment, initiator: peer, responder: me,
                initiatorKey: publicKey, initiatorNonce: nonce,
                responderKey: privateKey.publicKey.rawRepresentation, responderNonce: self.nonce, theirKey: publicKey)
            return nil

        case (_, .confirm(let mac)):
            guard let keys, !peerConfirmed else { throw .unexpectedMessage }
            let expected = Self.confirmation(for: role == .initiator ? .responder : .initiator, keys: keys)
            guard mac == expected else { throw .badConfirmation }
            peerConfirmed = true
            finishIfReady()
            return nil

        default:
            throw .unexpectedMessage
        }
    }

    /// The user confirmed the codes match on this Mac. Returns the confirmation to send.
    public mutating func accept() throws(Failure) -> Message {
        guard let keys, !accepted else { throw .unexpectedMessage }
        accepted = true
        finishIfReady()
        return .confirm(mac: Self.confirmation(for: role, keys: keys))
    }

    private mutating func finishIfReady() {
        guard accepted, peerConfirmed, let keys, let peer else { return }
        pairing = Pairing(peer: peer, key: keys.link)
    }

    private mutating func derive(
        commitment: Data, initiator: PeerIdentity, responder: PeerIdentity,
        initiatorKey: Data, initiatorNonce: Data, responderKey: Data, responderNonce: Data, theirKey: Data
    ) throws(Failure) {
        guard initiatorNonce.count == 16, responderNonce.count == 16,
            let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirKey),
            let shared = try? privateKey.sharedSecretFromKeyAgreement(with: theirs)
        else { throw .badKey }

        var transcript = Data("glazer pairing 1".utf8)
        for part in [
            commitment, Data(initiator.id.utf8), Data(initiator.name.utf8), Data(responder.id.utf8),
            Data(responder.name.utf8), initiatorKey, initiatorNonce, responderKey, responderNonce,
        ] {
            transcript.append(contentsOf: withUnsafeBytes(of: UInt32(part.count).bigEndian, Array.init))
            transcript.append(part)
        }
        let digest = Data(SHA256.hash(data: transcript))

        func derived(_ label: String, _ count: Int) -> Data {
            shared.hkdfDerivedSymmetricKey(
                using: SHA256.self, salt: digest, sharedInfo: Data(label.utf8), outputByteCount: count
            ).withUnsafeBytes { Data($0) }
        }
        let codeBytes = derived("glazer pairing code", 8)
        let number = codeBytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) } % 1_000_000
        code = String(format: "%06llu", number)
        keys = (SymmetricKey(data: derived("glazer pairing confirm", 32)), derived("glazer link key", 32), digest)
    }

    private static func commit(publicKey: Data, nonce: Data) -> Data {
        Data(SHA256.hash(data: publicKey + nonce))
    }

    private static func confirmation(
        for role: Role, keys: (confirm: SymmetricKey, link: Data, transcript: Data)
    ) -> Data {
        let label = Data((role == .initiator ? "initiator accepts" : "responder accepts").utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: label + keys.transcript, using: keys.confirm))
    }

    static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}
