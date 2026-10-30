import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// Runs linked Macs: the link, which Mac the user is at, forwarding the keyboard and mouse
/// there, carrying the clipboard, and screenshots grabbed on one Mac and dropped on
/// another. See docs/adr/0010.
@MainActor
@Observable
final class LinkController {
    /// Macs nearby, paired Macs and links, mirrored from the service for the interface.
    private(set) var nearby: [LinkService.Nearby] = []
    private(set) var paired: [PeerStore.Peer] = []
    private(set) var linked: [String: PeerIdentity] = [:]
    /// The linked Mac the user is at, or `nil` for this one.
    private(set) var target: PeerIdentity?
    /// Whether this Mac's keyboard and mouse are going to ``target`` now.
    private(set) var isForwarding = false
    /// A linked Mac using its keyboard and mouse here now, if any.
    private(set) var controlledBy: PeerIdentity?
    /// Pairing being shown: started here, or asked for by another Mac.
    private(set) var pairing: PairingModel?

    var isRunning: Bool {
        service != nil
    }

    // Settings, set by the app model.
    @ObservationIgnored var forwardsInput = true
    @ObservationIgnored var acceptsInput = true
    @ObservationIgnored var sharesClipboard = true

    /// Hooks into the rest of the app.
    @ObservationIgnored var onRemoteGrab: ((Bool) -> Void)?
    @ObservationIgnored var deliverScreenshot: ((Data) -> Void)?
    @ObservationIgnored var takeHeldScreenshot: (() async -> Data?)?
    /// Told when the keyboard and mouse start or stop going to a linked Mac.
    @ObservationIgnored var onForwardingChanged: ((PeerIdentity?) -> Void)?

    @ObservationIgnored private var service: LinkService?
    @ObservationIgnored private var arbiter = LinkArbiter()
    @ObservationIgnored private let forwarder = InputForwarder()
    @ObservationIgnored private let replayer = InputReplayer()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var lastPresence = Presence.unknown
    @ObservationIgnored private var lastPresenceSent = Date.distantPast
    /// The grab this Mac holds and has told linked Macs about.
    @ObservationIgnored private var heldGrab: UUID?
    /// A grab held on a linked Mac, and which one.
    @ObservationIgnored private var remoteGrab: (id: UUID, holder: String)?
    /// Screenshots already dropped here, so one sent twice lands once.
    @ObservationIgnored private var delivered: Set<UUID> = []
    /// The clipboard's change count when it last came from, or went to, another Mac.
    @ObservationIgnored private var clipboardSynced = -1

    // MARK: Running

    func start(as me: PeerIdentity) {
        guard service == nil else { return }
        let service = LinkService(me: me)
        service.onEvent = { [weak self] event in self?.handle(event) }
        self.service = service
        service.start()
        forwarder.localShortcut = (UInt16(KeyCodes.code(for: "G") ?? 5), [.maskAlternate, .maskCommand])
        forwarder.onEvent = { [weak self] input in self?.forward(input) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // On quit, let go of anything held on the other Mac.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        refresh()
    }

    func stop() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        stopForwarding()
        replayer.releaseAll()
        forwarder.stop()
        timer?.invalidate()
        timer = nil
        service?.stop()
        service = nil
        arbiter = LinkArbiter()
        target = nil
        controlledBy = nil
        heldGrab = nil
        remoteGrab = nil
        pairing?.attempt.decline()
        pairing = nil
        refresh()
    }

    // MARK: Pairing

    func pair(with nearby: LinkService.Nearby) {
        guard let attempt = service?.pair(with: nearby) else { return }
        show(attempt)
    }

    func unpair(_ id: String) {
        service?.unpair(id)
    }

    func closePairing() {
        if let pairing, !pairing.isFinished {
            pairing.attempt.decline()
        }
        pairing = nil
    }

    private func show(_ attempt: PairingAttempt) {
        pairing?.attempt.decline()
        pairing = PairingModel(attempt: attempt)
        PairingWindow.shared.show(controller: self)
    }

    // MARK: Where the user is

    /// The user's head, as this Mac's engine sees it: how far from this Mac's nearest
    /// display, or `nil` with nobody followed.
    func updatePresence(distance: Double?) {
        let presence = Presence(distance: distance)
        let now = ProcessInfo.processInfo.systemUptime
        arbiter.updateLocal(presence, at: now)
        if presence.isFaced != lastPresence.isFaced || Date().timeIntervalSince(lastPresenceSent) >= 1 {
            service?.broadcast(.presence(presence))
            lastPresenceSent = Date()
        }
        lastPresence = presence
    }

    /// Moves the user to the next Mac, as the switch shortcut does after the last display.
    /// Returns whether it moved them: `false` when there's no linked Mac.
    func chooseNext() -> Bool {
        let ids = arbiter.peerIDs
        guard !ids.isEmpty else { return false }
        let next: String? =
            if let current = target?.id, let index = ids.firstIndex(of: current) {
                index + 1 < ids.count ? ids[index + 1] : nil
            } else {
                ids.first
            }
        arbiter.choose(next, at: ProcessInfo.processInfo.systemUptime)
        apply(next)
        return true
    }

    /// Whether the user is at a linked Mac rather than this one.
    var isAway: Bool {
        target != nil
    }

    private func tick() {
        guard service != nil else { return }
        // Never switch mid-word or mid-drag.
        guard !forwarder.isBusy else { return }
        apply(arbiter.decide(at: ProcessInfo.processInfo.systemUptime))
    }

    private func apply(_ id: String?) {
        let newTarget = id.flatMap { linked[$0] }
        guard newTarget?.id != target?.id else { return }
        let old = target
        target = newTarget
        Logger.link.notice("User is at \(newTarget?.name ?? "this Mac", privacy: .public)")

        if let old {
            stopForwarding(to: old)
        }
        if let newTarget, forwardsInput {
            startForwarding(to: newTarget)
        }
    }

    // MARK: Keyboard and mouse

    private func startForwarding(to peer: PeerIdentity) {
        guard forwarder.start() else { return }
        if sharesClipboard {
            sendClipboard(to: peer.id, force: false)
        }
        forwarder.setForwarding(true)
        isForwarding = true
        onForwardingChanged?(peer)
    }

    private func stopForwarding(to peer: PeerIdentity? = nil) {
        guard isForwarding else { return }
        forwarder.setForwarding(false)
        isForwarding = false
        onForwardingChanged?(nil)
        if let peer = peer ?? target {
            service?.send(.releaseInput, to: peer.id)
            if sharesClipboard {
                service?.send(.clipboardRequest, to: peer.id)
            }
        }
    }

    private func forward(_ input: InputEvent) {
        guard let target else { return }
        service?.send(.input(input), to: target.id)
    }

    // MARK: Clipboard

    private func sendClipboard(to peer: String, force: Bool) {
        let count = ClipboardBridge.changeCount()
        guard force || count != clipboardSynced, let contents = ClipboardBridge.read(),
            let data = try? contents.encoded()
        else {
            service?.send(.clipboard(changed: false), to: peer)
            return
        }
        clipboardSynced = count
        service?.send(.clipboard(changed: true), payload: data, to: peer)
    }

    private func receiveClipboard(_ payload: Data) {
        guard sharesClipboard, let contents = try? ClipboardContents.decode(payload) else { return }
        clipboardSynced = ClipboardBridge.write(contents)
    }

    // MARK: Screenshots

    /// This Mac grabbed a screenshot: tell linked Macs, so the one the user turns to can
    /// catch the drop.
    func screenshotHeld() {
        let grab = UUID()
        heldGrab = grab
        service?.broadcast(.holding(grab: grab))
    }

    /// This Mac's grab ended here, dropped or cancelled.
    func screenshotReleased() {
        guard let grab = heldGrab else { return }
        heldGrab = nil
        service?.broadcast(.released(grab: grab))
    }

    /// The hand opened, seen by this Mac's camera. Returns whether the drop belongs to a
    /// linked Mac, which is then handled here; otherwise the drop is local.
    func dropped(remoteHold: Bool) -> Bool {
        if remoteHold, let remoteGrab {
            // A grab from another Mac, dropped here: ask for it.
            service?.send(.claim(grab: remoteGrab.id), to: remoteGrab.holder)
            return true
        }
        if let target, heldGrab != nil {
            // Grabbed here, dropped while the user is at another Mac: send it there.
            send(heldTo: target.id)
            return true
        }
        return false
    }

    private func send(heldTo peer: String) {
        guard let grab = heldGrab else { return }
        heldGrab = nil
        Task {
            guard let png = await takeHeldScreenshot?() else { return }
            service?.send(.screenshot(grab: grab), payload: png, to: peer)
            service?.broadcast(.released(grab: grab))
            Logger.link.notice("Sent a screenshot to \(self.linked[peer]?.name ?? peer, privacy: .public)")
        }
    }

    // MARK: Messages

    private func handle(_ event: LinkService.Event) {
        switch event {
        case .linked:
            break
        case .unlinked(let peer):
            arbiter.remove(peer: peer.id)
            if target?.id == peer.id {
                forwarder.setForwarding(false)
                if isForwarding { onForwardingChanged?(nil) }
                isForwarding = false
                target = nil
            }
            if controlledBy?.id == peer.id {
                replayer.releaseAll()
                controlledBy = nil
            }
            if remoteGrab?.holder == peer.id {
                remoteGrab = nil
                onRemoteGrab?(false)
            }
        case .pairingRequest(let attempt):
            NSApp.activate()
            show(attempt)
        case .changed:
            break
        case .message(let message, let payload, let peer):
            receive(message, payload: payload, from: peer)
        }
        refresh()
    }

    private func receive(_ message: LinkMessage, payload: Data, from peer: PeerIdentity) {
        switch message {
        case .presence(let presence):
            arbiter.update(peer: peer.id, presence, at: ProcessInfo.processInfo.systemUptime)

        case .input(let input):
            guard acceptsInput else { return }
            controlledBy = peer
            replayer.replay(input)
        case .releaseInput:
            replayer.releaseAll()
            if controlledBy?.id == peer.id { controlledBy = nil }

        case .clipboard(let changed):
            if changed { receiveClipboard(payload) }
        case .clipboardRequest:
            if sharesClipboard { sendClipboard(to: peer.id, force: false) }

        case .holding(let grab):
            remoteGrab = (grab, peer.id)
            onRemoteGrab?(true)
        case .released(let grab):
            if remoteGrab?.id == grab {
                remoteGrab = nil
                onRemoteGrab?(false)
            }
        case .claim(let grab):
            if heldGrab == grab { send(heldTo: peer.id) }
        case .screenshot(let grab):
            guard !delivered.contains(grab) else { return }
            delivered.insert(grab)
            if remoteGrab?.id == grab {
                remoteGrab = nil
                onRemoteGrab?(false)
            }
            Logger.link.notice("Received a screenshot from \(peer.name, privacy: .public)")
            deliverScreenshot?(payload)

        case .hello, .heartbeat, .unpair, .pairing:
            break
        }
    }

    private func refresh() {
        nearby = service?.nearby ?? []
        paired = service?.paired ?? []
        linked = service?.linked ?? [:]
        let unpairedNearby = Set(paired.map(\.identity.id))
        nearby = nearby.filter { !unpairedNearby.contains($0.id) }
        // The keyboard and mouse tap is only needed while a Mac is linked.
        if linked.isEmpty {
            stopForwarding()
            forwarder.stop()
        } else if forwardsInput {
            forwarder.start()
        }
    }
}

/// A pairing attempt, observed for the interface.
@MainActor
@Observable
final class PairingModel {
    let attempt: PairingAttempt
    private(set) var state: PairingAttempt.State

    init(attempt: PairingAttempt) {
        self.attempt = attempt
        state = attempt.state
        attempt.onChange = { [weak self] state in self?.state = state }
    }

    var isFinished: Bool {
        switch state {
        case .paired, .failed: true
        default: false
        }
    }
}

extension Logger {
    static let link = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "link")
}
