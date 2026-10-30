import Foundation
import GlazerCore
import Testing

@testable import GlazerSystem

/// Waits up to `seconds` for `condition`, checking every 50 ms.
@MainActor
private func eventually(_ seconds: Double = 15, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

/// Two link services on this Mac, each with its own Keychain items and Bonjour types, so
/// they find only each other and touch nothing of Glazer's.
@MainActor
private final class Pair {
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let a: LinkService
    let b: LinkService
    let storeA: PeerStore
    let storeB: PeerStore
    var requests: [PairingAttempt] = []
    var received: [(LinkMessage, Data)] = []

    init() {
        storeA = PeerStore(service: "io.github.phanipaladugula.glazer.tests.link-a-\(suffix)")
        storeB = PeerStore(service: "io.github.phanipaladugula.glazer.tests.link-b-\(suffix)")
        // IDs ordered so A connects and B accepts.
        let linkType = "_gz\(suffix.prefix(6))._tcp"
        let pairingType = "_gp\(suffix.prefix(6))._tcp"
        a = LinkService(
            me: PeerIdentity(id: "A-\(suffix)", name: "Test A"), store: storeA, linkType: linkType,
            pairingType: pairingType)
        b = LinkService(
            me: PeerIdentity(id: "B-\(suffix)", name: "Test B"), store: storeB, linkType: linkType,
            pairingType: pairingType)
        b.onEvent = { [weak self] event in
            switch event {
            case .pairingRequest(let attempt): self?.requests.append(attempt)
            case .message(let message, let payload, _): self?.received.append((message, payload))
            default: break
            }
        }
    }

    func tearDown() {
        a.stop()
        b.stop()
        try? storeA.removeAll()
        try? storeB.removeAll()
    }
}

@Suite("Link service", .serialized, .enabled(if: keychainAvailableForLink))
@MainActor
struct LinkServiceTests {
    @Test("Two Macs find each other, pair with matching codes, link and talk")
    func pairAndLink() async throws {
        let pair = Pair()
        defer { pair.tearDown() }
        pair.a.start()
        pair.b.start()

        #expect(await eventually { pair.a.nearby.contains { $0.id == pair.b.me.id } })
        let nearby = try #require(pair.a.nearby.first { $0.id == pair.b.me.id })
        #expect(nearby.name == "Test B")

        let outgoing = try #require(pair.a.pair(with: nearby))
        #expect(await eventually { !pair.requests.isEmpty })
        let incoming = try #require(pair.requests.first)

        guard case .confirming(let codeA) = outgoing.state, case .confirming(let codeB) = incoming.state else {
            Issue.record("Both should show a code: \(outgoing.state), \(incoming.state)")
            return
        }
        #expect(codeA == codeB)
        #expect(incoming.peer?.id == pair.a.me.id)

        outgoing.accept()
        incoming.accept()
        #expect(await eventually { outgoing.state == .paired(pair.b.me) && incoming.state == .paired(pair.a.me) })
        #expect(try pair.storeA.peers().map(\.identity) == [pair.b.me])
        #expect(try pair.storeA.peers().first?.key == pair.storeB.peers().first?.key)

        // Linked over TLS with the paired key.
        #expect(await eventually { pair.a.linked[pair.b.me.id] != nil && pair.b.linked[pair.a.me.id] != nil })

        let grab = UUID()
        pair.a.send(.screenshot(grab: grab), payload: Data(repeating: 9, count: 300_000), to: pair.b.me.id)
        pair.a.broadcast(.presence(Presence(distance: 0)))
        #expect(await eventually { pair.received.count >= 2 })
        #expect(pair.received.first?.0 == .screenshot(grab: grab))
        #expect(pair.received.first?.1.count == 300_000)
        #expect(pair.received.last?.0 == .presence(Presence(distance: 0)))

        // Unpairing on one Mac forgets it on both.
        pair.a.unpair(pair.b.me.id)
        #expect(await eventually { (try? pair.storeB.peers().isEmpty) == true })
        #expect(await eventually { pair.b.linked.isEmpty && pair.a.linked.isEmpty })
    }

    @Test("Declining on either Mac ends pairing on both, and stores nothing")
    func decline() async throws {
        let pair = Pair()
        defer { pair.tearDown() }
        pair.a.start()
        pair.b.start()

        #expect(await eventually { pair.a.nearby.contains { $0.id == pair.b.me.id } })
        let target = try #require(pair.a.nearby.first)
        let outgoing = try #require(pair.a.pair(with: target))
        #expect(await eventually { !pair.requests.isEmpty })

        pair.requests[0].decline()
        #expect(await eventually { outgoing.state == .failed(.declined) })
        #expect(try pair.storeA.peers().isEmpty)
        #expect(try pair.storeB.peers().isEmpty)
    }
}

/// Whether this machine's Keychain accepts items without asking, as on CI and developer Macs.
let keychainAvailableForLink: Bool = {
    let store = PeerStore(service: "io.github.phanipaladugula.glazer.tests.link-probe-\(UUID())")
    do {
        try store.save(PeerStore.Peer(identity: PeerIdentity(id: "probe", name: "probe"), key: Data([1])))
        try store.removeAll()
        return true
    } catch {
        return false
    }
}()
