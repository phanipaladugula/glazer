import CryptoKit
import Foundation

/// Whether the user faces this Mac, as one Mac tells its linked Macs.
public struct Presence: Codable, Equatable, Sendable {
    /// Whether the user's head is within a few degrees of one of this Mac's displays.
    public var isFaced: Bool
    /// How far, in degrees, the user's head is from this Mac's nearest display region: 0
    /// inside it. `nil` when no face is followed.
    public var distance: Double?

    public init(isFaced: Bool, distance: Double?) {
        self.isFaced = isFaced
        self.distance = distance
    }

    public static let unknown = Presence(isFaced: false, distance: nil)

    /// How near, in degrees, a display's region the head must be for the Mac to count as
    /// faced. Small, so that looking just past a display's edge towards another Mac
    /// doesn't count.
    public static let facedWithin = 6.0

    public init(distance: Double?) {
        self.init(isFaced: distance.map { $0 <= Self.facedWithin } ?? false, distance: distance)
    }
}

/// What linked Macs say to each other. Each travels as one ``LinkFrame``, some with bytes
/// attached, such as a screenshot's PNG.
public enum LinkMessage: Codable, Equatable, Sendable {
    /// The first message on a link, from each side, with proof the sender holds the key
    /// paired with it (``LinkProof``).
    case hello(PeerIdentity, version: Int, proof: Data)
    /// Sent every second, so a silent link can be told from a quiet one.
    case heartbeat
    /// Whether the user faces the sender. Sent when it changes, and with every heartbeat.
    case presence(Presence)
    /// The sender holds a screenshot the user grabbed.
    case holding(grab: UUID)
    /// The screenshot the sender held was dropped somewhere, or the grab was cancelled.
    case released(grab: UUID)
    /// The user dropped the held screenshot on the sender: send it.
    case claim(grab: UUID)
    /// A screenshot, as PNG, attached. The receiver pastes or shows it.
    case screenshot(grab: UUID)
    /// A key, button, pointer movement or scroll, to replay.
    case input(InputEvent)
    /// Forwarding stopped: release every key and button the sender's input is holding.
    case releaseInput
    /// Control moves to the receiver, with the sender's clipboard attached if it changed.
    case clipboard(changed: Bool)
    /// Control comes back to the sender: reply with ``clipboard(changed:)``.
    case clipboardRequest
    /// The sender forgot this pairing. The receiver forgets it too.
    case unpair
    /// A pairing exchange, on the separate pairing connection before Macs are linked.
    case pairing(PairingSession.Message)

    /// The protocol version in ``hello(_:version:proof:)``. A Mac refuses a link with another
    /// version, rather than misread it.
    public static let version = 1
}

/// Proof, in a link's hello, that the sender is the paired Mac it says it is.
///
/// TLS already admits only Macs holding some paired key. The proof ties the link to the
/// key paired with the Mac the hello names, so one paired Mac can't pass itself off as
/// another.
public enum LinkProof {
    public static func make(key: Data, from sender: String, to receiver: String) -> Data {
        let message = Data("glazer hello \(sender) to \(receiver)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    public static func check(_ proof: Data, key: Data, from sender: String, to receiver: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof, authenticating: Data("glazer hello \(sender) to \(receiver)".utf8), using: SymmetricKey(data: key))
    }
}

/// A message and the bytes attached to it, in the form sent on a link: a 4-byte header
/// length, a 4-byte payload length, the message as JSON, then the payload.
public enum LinkFrame {
    public enum Failure: Error, Equatable, Sendable {
        case tooLarge
        case unreadable
    }

    /// The largest message, without its attachment.
    public static let maximumHeader = 64 * 1024
    /// The largest attachment.
    public static let maximumPayload = 64 * 1024 * 1024

    public static func encode(_ message: LinkMessage, payload: Data = Data()) throws -> Data {
        let header = try JSONEncoder().encode(message)
        guard header.count <= maximumHeader, payload.count <= maximumPayload else { throw Failure.tooLarge }
        var frame = Data(capacity: 8 + header.count + payload.count)
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(header.count).bigEndian, Array.init))
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian, Array.init))
        frame.append(header)
        frame.append(payload)
        return frame
    }

    /// Collects bytes as they arrive and returns whole frames.
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        /// Adds `bytes` and returns every frame now complete, in order. Throws on a frame
        /// too large or unreadable; the link should then be closed.
        public mutating func add(_ bytes: Data) throws(Failure) -> [(message: LinkMessage, payload: Data)] {
            buffer.append(bytes)
            var frames: [(LinkMessage, Data)] = []
            while buffer.count >= 8 {
                let headerLength = Int(Self.uint32(buffer, at: 0))
                let payloadLength = Int(Self.uint32(buffer, at: 4))
                guard headerLength <= maximumHeader, payloadLength <= maximumPayload else { throw .tooLarge }
                guard buffer.count >= 8 + headerLength + payloadLength else { break }

                let start = buffer.startIndex
                let header = buffer[(start + 8)..<(start + 8 + headerLength)]
                let payload = Data(buffer[(start + 8 + headerLength)..<(start + 8 + headerLength + payloadLength)])
                guard let message = try? JSONDecoder().decode(LinkMessage.self, from: Data(header)) else {
                    throw .unreadable
                }
                frames.append((message, payload))
                buffer = Data(buffer[(start + 8 + headerLength + payloadLength)...])
            }
            return frames
        }

        private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
            data[(data.startIndex + offset)..<(data.startIndex + offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
        }
    }
}
