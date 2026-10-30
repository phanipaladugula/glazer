import Foundation
import Testing

@testable import GlazerCore

private let laptop = PeerIdentity(id: "A", name: "MacBook")
private let desktop = PeerIdentity(id: "B", name: "iMac")

/// Runs the exchange up to showing the codes, and returns both sides.
private func exchange() throws -> (initiator: PairingSession, responder: PairingSession) {
    var initiator = PairingSession(role: .initiator, me: laptop)
    var responder = PairingSession(role: .responder, me: desktop)
    let commit = initiator.start()
    let key = try #require(try responder.receive(commit))
    let reveal = try #require(try initiator.receive(key))
    #expect(try responder.receive(reveal) == nil)
    return (initiator, responder)
}

@Suite("Pairing")
struct PairingSessionTests {
    @Test("Both Macs show the same six-digit code and learn who the other is")
    func sameCode() throws {
        let (initiator, responder) = try exchange()

        let code = try #require(initiator.code)
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        #expect(responder.code == code)
        #expect(initiator.peer == desktop)
        #expect(responder.peer == laptop)
    }

    @Test("Each pairing has a fresh code")
    func freshCodes() throws {
        let codes = try (0..<5).map { _ in try exchange().initiator.code }

        #expect(Set(codes).count > 1)
    }

    @Test("Once both confirm, both hold the same 32-byte key")
    func pairs() throws {
        var (initiator, responder) = try exchange()
        let fromInitiator = try initiator.accept()
        #expect(initiator.pairing == nil)
        let fromResponder = try responder.accept()
        _ = try responder.receive(fromInitiator)
        _ = try initiator.receive(fromResponder)

        let left = try #require(initiator.pairing)
        let right = try #require(responder.pairing)
        #expect(left.key == right.key)
        #expect(left.key.count == 32)
        #expect(left.peer == desktop && right.peer == laptop)
    }

    @Test("A confirmation can't be turned around and sent back as the other side's")
    func reflectedConfirmation() throws {
        var (initiator, _) = try exchange()
        let mine = try initiator.accept()

        #expect(throws: PairingSession.Failure.badConfirmation) { try initiator.receive(mine) }
    }

    @Test("A machine in the middle gets different codes on each side")
    func manInTheMiddle() throws {
        // The middle runs a responder towards the laptop and an initiator towards the iMac.
        var initiator = PairingSession(role: .initiator, me: laptop)
        var middleAsResponder = PairingSession(role: .responder, me: desktop)
        var middleAsInitiator = PairingSession(role: .initiator, me: laptop)
        var responder = PairingSession(role: .responder, me: desktop)

        let key = try #require(try middleAsResponder.receive(initiator.start()))
        _ = try middleAsResponder.receive(try #require(try initiator.receive(key)))
        let otherKey = try #require(try responder.receive(middleAsInitiator.start()))
        _ = try responder.receive(try #require(try middleAsInitiator.receive(otherKey)))

        #expect(initiator.code != responder.code)

        // A confirmation from one side's session doesn't verify on the other's.
        let fromMiddle = try middleAsInitiator.accept()
        _ = try responder.accept()
        #expect(throws: PairingSession.Failure.badConfirmation) {
            var initiatorCopy = initiator
            _ = try initiatorCopy.receive(fromMiddle)
        }
    }

    @Test("A key revealed that differs from the commitment is refused")
    func commitment() throws {
        var initiator = PairingSession(role: .initiator, me: laptop)
        var responder = PairingSession(role: .responder, me: desktop)
        let key = try #require(try responder.receive(initiator.start()))
        guard case .reveal(_, let nonce) = try #require(try initiator.receive(key)) else {
            Issue.record("Expected a reveal")
            return
        }
        let swapped = PairingSession.Message.reveal(publicKey: PairingSession.randomBytes(32), nonce: nonce)
        #expect(throws: PairingSession.Failure.commitmentMismatch) { try responder.receive(swapped) }
    }

    @Test("Messages out of order are refused")
    func order() throws {
        var initiator = PairingSession(role: .initiator, me: laptop)
        var responder = PairingSession(role: .responder, me: desktop)

        #expect(throws: PairingSession.Failure.unexpectedMessage) {
            try initiator.receive(.reveal(publicKey: Data(), nonce: Data()))
        }
        #expect(throws: PairingSession.Failure.unexpectedMessage) { try responder.accept() }
        #expect(throws: PairingSession.Failure.unexpectedMessage) {
            try responder.receive(.confirm(mac: Data()))
        }
        let commit = initiator.start()
        _ = try responder.receive(commit)
        #expect(throws: PairingSession.Failure.unexpectedMessage) { try responder.receive(commit) }
    }

    @Test("A bad key is refused")
    func badKey() throws {
        var initiator = PairingSession(role: .initiator, me: laptop)
        _ = initiator.start()

        #expect(throws: PairingSession.Failure.badKey) {
            try initiator.receive(.key(desktop, publicKey: Data([1, 2, 3]), nonce: PairingSession.randomBytes(16)))
        }
    }

    @Test("A decline ends pairing")
    func decline() {
        var responder = PairingSession(role: .responder, me: desktop)

        #expect(throws: PairingSession.Failure.declined) { try responder.receive(.decline) }
    }

    @Test("Accepting twice is refused")
    func acceptTwice() throws {
        var (initiator, _) = try exchange()
        _ = try initiator.accept()

        #expect(throws: PairingSession.Failure.unexpectedMessage) { try initiator.accept() }
    }

    @Test("Messages survive encoding")
    func codable() throws {
        var initiator = PairingSession(role: .initiator, me: laptop)
        let message = initiator.start()
        let data = try JSONEncoder().encode(message)

        #expect(try JSONDecoder().decode(PairingSession.Message.self, from: data) == message)
    }
}
