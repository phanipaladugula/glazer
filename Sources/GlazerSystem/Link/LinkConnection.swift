import Foundation
import GlazerCore
import Network
import OSLog

/// One connection to another Mac, carrying ``LinkFrame``s: the pairing channel, or a
/// link once paired.
@MainActor
final class LinkConnection {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((LinkMessage, Data) -> Void)?
    /// Called once, when the connection ends for any reason.
    var onClose: (() -> Void)?

    /// When anything last arrived.
    private(set) var lastReceived = Date()
    private var reader = LinkFrame.Reader()
    private var isClosed = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.lastReceived = Date()
                    self.onReady?()
                    self.receive()
                case .failed(let error):
                    Logger.link.notice("Connection failed: \(error.localizedDescription, privacy: .public)")
                    self.close()
                case .waiting(let error):
                    // TLS refusing an unknown key, or the other Mac gone: don't wait around.
                    Logger.link.notice("Connection waiting: \(error.localizedDescription, privacy: .public)")
                    self.close()
                case .cancelled:
                    self.close()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    func send(_ message: LinkMessage, payload: Data = Data()) {
        guard !isClosed else { return }
        do {
            let frame = try LinkFrame.encode(message, payload: payload)
            connection.send(
                content: frame,
                completion: .contentProcessed { [weak self] error in
                    guard let error else { return }
                    MainActor.assumeIsolated {
                        Logger.link.notice("Send failed: \(error.localizedDescription, privacy: .public)")
                        self?.close()
                    }
                })
        } catch {
            Logger.link.error("Couldn't send a message: \(String(describing: error), privacy: .public)")
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let onClose = onClose
        self.onClose = nil
        onMessage = nil
        onClose?()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.lastReceived = Date()
                    do {
                        for frame in try self.reader.add(data) {
                            self.onMessage?(frame.message, frame.payload)
                            if self.isClosed { return }
                        }
                    } catch {
                        Logger.link.error(
                            "Unreadable data from a linked Mac: \(String(describing: error), privacy: .public)")
                        self.close()
                        return
                    }
                }
                if isComplete || error != nil {
                    self.close()
                } else {
                    self.receive()
                }
            }
        }
    }
}

extension Logger {
    static let link = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "link")
}
