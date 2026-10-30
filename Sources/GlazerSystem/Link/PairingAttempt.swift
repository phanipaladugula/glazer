import Foundation
import GlazerCore
import Network
import OSLog

/// Pairing with one other Mac, from either side: the exchange, the code both users
/// compare, and their answers.
@MainActor
public final class PairingAttempt: Identifiable {
    public enum State: Equatable, Sendable {
        /// Connecting, or exchanging keys.
        case connecting
        /// Both Macs show `code`. Waiting for the user here to confirm.
        case confirming(code: String)
        /// The user here confirmed; waiting for the other Mac.
        case waitingForOther(code: String)
        case paired(PeerIdentity)
        case failed(Failure)
    }

    public enum Failure: Equatable, Sendable {
        /// Someone declined, here or on the other Mac.
        case declined
        /// The codes didn't match, or the exchange was tampered with.
        case mismatch
        /// The other Mac couldn't be reached, or went away.
        case connectionLost
        /// Nobody answered in time.
        case timedOut
        /// The pairing couldn't be saved to the Keychain.
        case couldNotSave
    }

    public let id = UUID()
    /// The other Mac, once known. The initiator knows it from the start.
    public private(set) var peer: PeerIdentity?
    public private(set) var state: State = .connecting {
        didSet { onChange?(state) }
    }
    /// Called on every change of ``state``.
    public var onChange: ((State) -> Void)?

    private var session: PairingSession
    private let connection: LinkConnection
    private let store: PeerStore
    /// Called once paired and saved, so links can be made.
    var onPaired: ((PeerStore.Peer) -> Void)?
    private var timeout: Task<Void, Never>?

    /// How long pairing may wait for anyone before it gives up.
    static let timeLimit: Duration = .seconds(120)

    init(role: PairingSession.Role, me: PeerIdentity, peer: PeerIdentity?, connection: LinkConnection, store: PeerStore)
    {
        session = PairingSession(role: role, me: me)
        self.peer = peer
        self.connection = connection
        self.store = store

        connection.onMessage = { [weak self] message, _ in
            guard case .pairing(let message) = message else {
                self?.fail(.mismatch)
                return
            }
            self?.handle(message)
        }
        connection.onClose = { [weak self] in
            guard let self, !self.isFinished else { return }
            self.state = .failed(.connectionLost)
        }
        if role == .initiator {
            connection.onReady = { [weak self] in
                guard let self else { return }
                self.connection.send(.pairing(self.session.start()))
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.timeLimit)
            guard !Task.isCancelled else { return }
            self?.fail(.timedOut)
        }
    }

    /// The user here confirmed the codes match.
    public func accept() {
        guard case .confirming(let code) = state else { return }
        do {
            connection.send(.pairing(try session.accept()))
            state = .waitingForOther(code: code)
            finishIfPaired()
        } catch {
            fail(.mismatch)
        }
    }

    /// The user here declined, or closed the window.
    public func decline() {
        guard !isFinished else { return }
        connection.send(.pairing(.decline))
        fail(.declined)
    }

    var isFinished: Bool {
        switch state {
        case .paired, .failed: true
        default: false
        }
    }

    /// Starts reading the first message, for an attempt the other Mac started.
    func start() {
        connection.start()
    }

    func handle(_ message: PairingSession.Message) {
        guard !isFinished else { return }
        do {
            if let reply = try session.receive(message) {
                connection.send(.pairing(reply))
            }
        } catch {
            fail(error == .declined ? .declined : .mismatch)
            return
        }
        peer = session.peer ?? peer
        if case .connecting = state, let code = session.code {
            state = .confirming(code: code)
        }
        finishIfPaired()
    }

    private func finishIfPaired() {
        guard let pairing = session.pairing, !isFinished else { return }
        let peer = PeerStore.Peer(identity: pairing.peer, key: pairing.key)
        do {
            try store.save(peer)
        } catch {
            Logger.link.error("Couldn't save a pairing: \(String(describing: error), privacy: .public)")
            fail(.couldNotSave)
            return
        }
        timeout?.cancel()
        state = .paired(pairing.peer)
        Logger.link.notice("Paired with \(pairing.peer.name, privacy: .public)")
        // Let the last confirmation reach the other Mac before closing.
        Task { [connection] in
            try? await Task.sleep(for: .seconds(1))
            connection.close()
        }
        onPaired?(peer)
    }

    private func fail(_ failure: Failure) {
        guard !isFinished else { return }
        timeout?.cancel()
        state = .failed(failure)
        // A moment first, so a decline just sent reaches the other Mac.
        Task { [connection] in
            try? await Task.sleep(for: .milliseconds(300))
            connection.close()
        }
    }
}
