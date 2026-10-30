import Foundation
import GlazerCore
import Network
import OSLog

/// Finds other Macs running Glazer on the local network, pairs with them, and keeps an
/// encrypted link to each paired one that's around. See docs/adr/0010.
///
/// - **Discovery:** Bonjour, `_glazer._tcp` for links and `_glazer-pair._tcp` for
///   pairing. Each Mac advertises under its random device ID, with its name in the TXT
///   record, and nothing else.
/// - **Pairing:** a plain TCP connection carrying a ``PairingSession``; both users
///   confirm the code.
/// - **Links:** TLS with the key from pairing as a pre-shared key, so only paired Macs can
///   connect. The Mac with the lower device ID connects; the other accepts.
@MainActor
public final class LinkService {
    /// A Mac running Glazer with linking on, seen on the network.
    public struct Nearby: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
    }

    public enum Event {
        /// A paired Mac linked, or its link dropped.
        case linked(PeerIdentity)
        case unlinked(PeerIdentity)
        /// A message from a linked Mac, with its attachment.
        case message(LinkMessage, payload: Data, from: PeerIdentity)
        /// Another Mac asks to pair. Show its ``PairingAttempt``.
        case pairingRequest(PairingAttempt)
        /// The Macs nearby, the paired ones, or the links changed.
        case changed
    }

    public let me: PeerIdentity
    public var onEvent: ((Event) -> Void)?

    /// Macs nearby, paired or not.
    public private(set) var nearby: [Nearby] = []
    /// Paired Macs, linked or not.
    public private(set) var paired: [PeerStore.Peer] = []
    /// Paired Macs linked now, by ID.
    public private(set) var linked: [String: PeerIdentity] = [:]

    private let store: PeerStore
    private let linkType: String
    private let pairingType: String
    private var linkListener: NWListener?
    private var pairingListener: NWListener?
    private var linkBrowser: NWBrowser?
    private var pairingBrowser: NWBrowser?
    /// Where each paired Mac's link service was last seen.
    private var linkEndpoints: [String: NWEndpoint] = [:]
    private var pairingEndpoints: [String: NWEndpoint] = [:]
    /// Links up, by peer ID, and connections waiting for their hello.
    private var links: [String: LinkConnection] = [:]
    private var pending: [ObjectIdentifier: LinkConnection] = [:]
    /// Pairing that the other Mac started, at most one at a time.
    private var incomingPairing: PairingAttempt?
    private var heartbeat: Timer?
    private var isRunning = false

    /// How long a link may be silent before it's dropped. Heartbeats come every second.
    static let silenceLimit: TimeInterval = 5

    /// - Parameters:
    ///   - linkType, pairingType: Bonjour service types. Tests use their own.
    public init(
        me: PeerIdentity, store: PeerStore = PeerStore(), linkType: String = "_glazer._tcp",
        pairingType: String = "_glazer-pair._tcp"
    ) {
        self.me = me
        self.store = store
        self.linkType = linkType
        self.pairingType = pairingType
    }

    // MARK: Running

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        reloadPeers()
        startPairingListener()
        startLinkListener()
        linkBrowser = browse(linkType) { [weak self] found in
            self?.linkEndpoints = found.mapValues(\.endpoint)
            self?.connectToPeers()
        }
        pairingBrowser = browse(pairingType) { [weak self] found in
            guard let self else { return }
            pairingEndpoints = found.mapValues(\.endpoint)
            nearby = found.map { Nearby(id: $0.key, name: $0.value.name) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            onEvent?(.changed)
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        Logger.link.notice("Linking started as \(self.me.name, privacy: .public)")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        heartbeat?.invalidate()
        heartbeat = nil
        for listener in [linkListener, pairingListener] { listener?.cancel() }
        for browser in [linkBrowser, pairingBrowser] { browser?.cancel() }
        linkListener = nil
        pairingListener = nil
        linkBrowser = nil
        pairingBrowser = nil
        incomingPairing?.decline()
        incomingPairing = nil
        for connection in Array(links.values) + Array(pending.values) { connection.close() }
        links.removeAll()
        pending.removeAll()
        nearby.removeAll()
        linkEndpoints.removeAll()
        pairingEndpoints.removeAll()
        onEvent?(.changed)
    }

    // MARK: Sending

    public func send(_ message: LinkMessage, payload: Data = Data(), to peerID: String) {
        links[peerID]?.send(message, payload: payload)
    }

    public func broadcast(_ message: LinkMessage, payload: Data = Data()) {
        for link in links.values { link.send(message, payload: payload) }
    }

    // MARK: Pairing

    /// Starts pairing with a nearby Mac. Show the returned attempt; `nil` if the Mac has
    /// gone.
    public func pair(with nearby: Nearby) -> PairingAttempt? {
        guard let endpoint = pairingEndpoints[nearby.id] else { return nil }
        let connection = LinkConnection(NWConnection(to: endpoint, using: .tcp))
        let attempt = PairingAttempt(
            role: .initiator, me: me, peer: PeerIdentity(id: nearby.id, name: nearby.name),
            connection: connection, store: store)
        attempt.onPaired = { [weak self] _ in self?.pairingFinished() }
        connection.start()
        return attempt
    }

    /// Forgets a paired Mac, here and, if it's linked, there too.
    public func unpair(_ id: String) {
        links[id]?.send(.unpair)
        forget(id)
    }

    private func forget(_ id: String) {
        do {
            try store.remove(id: id)
        } catch {
            Logger.link.error("Couldn't remove a pairing: \(String(describing: error), privacy: .public)")
        }
        if let link = links[id] {
            // Let the unpair message go first.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                link.close()
            }
        }
        reloadPeers()
        restartLinkListener()
        onEvent?(.changed)
    }

    private func pairingFinished() {
        reloadPeers()
        restartLinkListener()
        connectToPeers()
        onEvent?(.changed)
    }

    private func reloadPeers() {
        do {
            paired = try store.peers()
        } catch {
            Logger.link.error("Couldn't read paired Macs: \(String(describing: error), privacy: .public)")
            paired = []
        }
    }

    // MARK: Listening

    private func startPairingListener() {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            Logger.link.error("Couldn't listen for pairing: \(error.localizedDescription, privacy: .public)")
            return
        }
        listener.service = service(pairingType)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.acceptPairing(connection) }
        }
        listener.start(queue: .main)
        pairingListener = listener
    }

    private func acceptPairing(_ nwConnection: NWConnection) {
        // One at a time: a second request while one is showing is turned away.
        if let incomingPairing, !incomingPairing.isFinished {
            nwConnection.cancel()
            return
        }
        let connection = LinkConnection(nwConnection)
        let attempt = PairingAttempt(role: .responder, me: me, peer: nil, connection: connection, store: store)
        attempt.onPaired = { [weak self] _ in self?.pairingFinished() }
        incomingPairing = attempt
        var announced = false
        attempt.onChange = { [weak self] state in
            // Tell the app once the code is known, which is when there's something to show.
            if case .confirming = state, !announced {
                announced = true
                self?.onEvent?(.pairingRequest(attempt))
            }
        }
        attempt.start()
    }

    private func startLinkListener() {
        guard !paired.isEmpty else { return }
        let listener: NWListener
        do {
            listener = try NWListener(using: Self.parameters(keys: paired.map { ($0.key, $0.identity.id) }))
        } catch {
            Logger.link.error("Couldn't listen for links: \(error.localizedDescription, privacy: .public)")
            return
        }
        listener.service = service(linkType)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        linkListener = listener
    }

    private func restartLinkListener() {
        linkListener?.cancel()
        linkListener = nil
        guard isRunning else { return }
        startLinkListener()
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = LinkConnection(nwConnection)
        let key = ObjectIdentifier(connection)
        pending[key] = connection
        connection.onMessage = { [weak self, weak connection] message, _ in
            guard let self, let connection else { return }
            // The other Mac says hello first; answer once its proof checks out.
            guard case .hello(let identity, let version, let proof) = message,
                version == LinkMessage.version,
                let peer = paired.first(where: { $0.identity.id == identity.id }),
                LinkProof.check(proof, key: peer.key, from: identity.id, to: me.id)
            else {
                Logger.link.notice("Refused a link that didn't prove its pairing")
                connection.close()
                return
            }
            pending[key] = nil
            connection.send(
                .hello(
                    me, version: LinkMessage.version, proof: LinkProof.make(key: peer.key, from: me.id, to: identity.id)
                ))
            established(connection, with: peer.identity)
        }
        connection.onClose = { [weak self] in self?.pending[key] = nil }
        connection.start()
    }

    // MARK: Connecting

    /// Connects to each paired Mac that's around and not linked, where this Mac is the one
    /// to connect.
    private func connectToPeers() {
        guard isRunning else { return }
        for peer in paired where links[peer.identity.id] == nil && me.id < peer.identity.id {
            guard let endpoint = linkEndpoints[peer.identity.id],
                !pending.values.contains(where: { $0.connection.endpoint == endpoint })
            else { continue }
            connect(to: peer, at: endpoint)
        }
    }

    private func connect(to peer: PeerStore.Peer, at endpoint: NWEndpoint) {
        let parameters = Self.parameters(keys: [(peer.key, me.id)])
        let connection = LinkConnection(NWConnection(to: endpoint, using: parameters))
        let key = ObjectIdentifier(connection)
        pending[key] = connection
        connection.onReady = { [weak self, weak connection] in
            guard let self, let connection else { return }
            connection.send(
                .hello(
                    me, version: LinkMessage.version,
                    proof: LinkProof.make(key: peer.key, from: me.id, to: peer.identity.id)))
        }
        connection.onMessage = { [weak self, weak connection] message, _ in
            guard let self, let connection else { return }
            guard case .hello(let identity, let version, let proof) = message, identity.id == peer.identity.id,
                version == LinkMessage.version,
                LinkProof.check(proof, key: peer.key, from: identity.id, to: me.id)
            else {
                Logger.link.notice("Refused a link to \(peer.identity.name, privacy: .public): bad hello")
                connection.close()
                return
            }
            pending[key] = nil
            established(connection, with: identity)
        }
        connection.onClose = { [weak self] in self?.pending[key] = nil }
        connection.start()
    }

    private func established(_ connection: LinkConnection, with peer: PeerIdentity) {
        links[peer.id]?.close()
        links[peer.id] = connection
        connection.onMessage = { [weak self] message, payload in
            guard let self else { return }
            switch message {
            case .heartbeat, .hello:
                break
            case .unpair:
                Logger.link.notice("\(peer.name, privacy: .public) unpaired")
                forget(peer.id)
            default:
                onEvent?(.message(message, payload: payload, from: peer))
            }
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection, links[peer.id] === connection else { return }
            links[peer.id] = nil
            linked[peer.id] = nil
            Logger.link.notice("Link to \(peer.name, privacy: .public) dropped")
            onEvent?(.unlinked(peer))
            onEvent?(.changed)
            // Try again shortly, if the Mac is still around.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.connectToPeers()
            }
        }
        linked[peer.id] = peer
        Logger.link.notice("Linked with \(peer.name, privacy: .public)")
        onEvent?(.linked(peer))
        onEvent?(.changed)
    }

    private func beat() {
        let now = Date()
        for (_, link) in links {
            if now.timeIntervalSince(link.lastReceived) > Self.silenceLimit {
                link.close()
            } else {
                link.send(.heartbeat)
            }
        }
        connectToPeers()
    }

    // MARK: Network setup

    private func service(_ type: String) -> NWListener.Service {
        // Named by device ID, which is unique, with the human name alongside.
        NWListener.Service(name: me.id, type: type, txtRecord: NWTXTRecord(["name": me.name]))
    }

    private func browse(
        _ type: String, onChange: @escaping @MainActor ([String: (endpoint: NWEndpoint, name: String)]) -> Void
    ) -> NWBrowser {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var found: [String: (NWEndpoint, String)] = [:]
                for result in results {
                    guard case .service(let id, _, _, _) = result.endpoint, id != self.me.id else { continue }
                    var name = id
                    if case .bonjour(let txt) = result.metadata, let named = txt["name"] {
                        name = named
                    }
                    found[id] = (result.endpoint, name)
                }
                onChange(found)
            }
        }
        browser.start(queue: .main)
        return browser
    }

    /// TLS with pre-shared keys, as `(key, identity)`. The listener holds one per paired
    /// Mac, identified by that Mac's ID; a Mac connecting offers its own ID and the key it
    /// shares with the listener.
    static func parameters(keys: [(key: Data, identity: String)]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        for (key, identity) in keys {
            let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
            let identityData = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(
                tls.securityProtocolOptions, keyData as __DispatchData, identityData as __DispatchData)
        }
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, suite)
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
