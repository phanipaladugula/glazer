import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// Runs the camera and the gaze engine, and moves focus when the engine decides to and the
/// user isn't typing.
///
/// The camera runs only in one of four modes: following the user, calibrating, enrolling
/// face lock, or calibrating hand gestures. Otherwise it is off.
///
/// While following with hand gestures on, it also watches the user's hand, and no one
/// else's, for a grab and a drop. Each goes to the display the hand was held towards when
/// it began, or failing that the display the user faced.
@MainActor
@Observable
final class GazeController {
    enum Mode: Equatable {
        case idle
        case following
        case calibrating
        case enrolling
        case calibratingHands
    }

    /// A hand gesture, with the display it's meant for.
    enum Gesture: Equatable {
        /// The user closed their hand while facing `display`.
        case grabbed(Display.ID)
        /// The user opened their hand again while facing `display`.
        case dropped(Display.ID)
        /// The grab was held too long, the hand went out of view, or gestures stopped.
        case cancelled
    }

    private(set) var mode: Mode = .idle

    /// The engine's latest output. `nil` while idle.
    private(set) var output: GazeEngine.Output?

    /// Details of the latest frame, for the diagnostics view.
    private(set) var diagnostics = Diagnostics()

    /// Set when the camera couldn't start, or stopped by itself.
    private(set) var cameraFailure: CameraFeed.Failure?

    struct Diagnostics: Equatable {
        var faceCount = 0
        var rawPose: HeadPose?
        var brightness = 0.0
        var matchScore: Double?
        var framesPerSecond = 0.0
        /// How open the nearest hand is, from 0 (fist) to 1 (open), while gestures are on.
        var handOpenness: Double?
        var isHoldingGrab = false
        /// The display the user's hand is held towards, when that's clear.
        var handAimedAt: Display.ID?
        /// Hands in view that aren't the user's.
        var otherHands = 0
    }

    /// Told about each hand gesture while following.
    @ObservationIgnored var onGesture: ((Gesture) -> Void)?

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let focus: FocusController
    @ObservationIgnored private let typing = TypingMonitor()
    @ObservationIgnored private var typingGuard = TypingGuard(focusedDisplay: nil)
    @ObservationIgnored private var engine: GazeEngine?
    @ObservationIgnored private var frameHandler: ((Frame, GazeEngine.Output?) -> Void)?
    @ObservationIgnored private var displays: [Display] = []
    @ObservationIgnored private var pointerDisplay: Display.ID?
    @ObservationIgnored private var frameTimes: [TimeInterval] = []
    /// Watches for grabs and drops while gestures are on.
    @ObservationIgnored private var grab: GrabDetector?
    /// Where the user looked lately, so a gesture goes where they faced when it began.
    @ObservationIgnored private var faced = DisplayHistory()
    /// Where the user held their hand for each display, if calibration could tell.
    @ObservationIgnored private var aim: HandAim?
    /// Which display the user's hand was held towards lately.
    @ObservationIgnored private var aimed = DisplayHistory()
    /// Where the user's face was last seen, and when. Hands are matched to it, and a
    /// raised hand often hides the face for a moment.
    @ObservationIgnored private var userFace: (bounds: CGRect, time: TimeInterval)?
    /// The user's hand in the latest frame.
    @ObservationIgnored private var userHand: HandReading?
    /// The user's hand when last found, and when, to keep following it while a grab is
    /// held if the face goes out of view.
    @ObservationIgnored private var lastUserHand: (hand: HandReading, time: TimeInterval)?
    /// The latest frame's width over its height.
    @ObservationIgnored private var aspectRatio = 16.0 / 9.0
    /// How the user's hand was found in the latest frame, for the log.
    @ObservationIgnored private var handSource = "none"
    /// When the hand was last logged while a grab was held.
    @ObservationIgnored private var lastHoldLog = -TimeInterval.infinity
    /// What following was last started with, so an unchanged request doesn't restart it.
    @ObservationIgnored private var followed: (displays: [Display], calibration: Calibration, verifier: FaceTemplate?)?
    /// Bumped on every start and stop, so a camera start that finishes late can tell it's
    /// been superseded.
    @ObservationIgnored private var generation = 0
    /// When the frontmost app turned Secure Event Input on, if it has.
    @ObservationIgnored private var secureInputSince: TimeInterval?
    /// Told when the camera stops by itself while calibrating or enrolling.
    @ObservationIgnored private var failureHandler: ((CameraFeed.Failure) -> Void)?

    /// The display that has focus: where Glazer last moved it, or where the user moved the
    /// pointer. A switch held back while the user types doesn't change it.
    private(set) var focusedDisplay: Display.ID?

    init(focus: FocusController) {
        self.focus = focus
    }

    // MARK: Modes

    /// Follows the user and moves focus between `displays`.
    ///
    /// Calling it again with the same displays, calibration and face lock only updates the
    /// switch delay, so the user stays followed.
    func follow(displays: [Display], calibration: Calibration, verifier: IdentityVerifier?, switchDelay: Double) {
        if mode == .following, let followed, followed.displays == displays,
            followed.calibration == calibration, followed.verifier == verifier?.template
        {
            engine?.setDwell(switchDelay)
            return
        }
        followed = (displays, calibration, verifier?.template)

        var classification = DisplayClassifier.Configuration()
        classification.dwell = switchDelay
        // Weight head turn and tilt by how the displays are arranged: stacked displays are
        // told apart by tilt, side-by-side ones by turn.
        classification.weights = AxisWeights(arranging: displays)
        // Only connected displays can be chosen: a disconnected display's calibration
        // point would otherwise send focus nowhere.
        var engine = GazeEngine(
            calibration: calibration.restricted(to: displays), verifier: verifier, classification: classification)

        self.displays = displays
        pointerDisplay = Self.displayUnderPointer(in: displays)
        focusedDisplay = pointerDisplay
        engine.setFocusedDisplay(pointerDisplay)
        typingGuard = TypingGuard(focusedDisplay: pointerDisplay)
        typing.start { [weak self] timestamp in
            self?.typingGuard.keyPressed(at: timestamp)
        }
        start(.following, engine: engine, handler: nil)
    }

    /// Reports the user's pose to `handler` on every frame, without moving focus.
    func calibrate(
        verifier: IdentityVerifier?, handler: @escaping (Frame, GazeEngine.Output?) -> Void,
        onFailure: @escaping (CameraFeed.Failure) -> Void
    ) {
        start(.calibrating, engine: GazeEngine(calibration: nil, verifier: verifier), handler: handler)
        failureHandler = onFailure
    }

    /// Reports every frame, with signatures for each face, to `handler`.
    func enroll(handler: @escaping (Frame, GazeEngine.Output?) -> Void) {
        start(.enrolling, engine: nil, handler: handler)
    }

    /// Reports every frame, with the nearest hand, to `handler`.
    func calibrateHands(handler: @escaping (Frame) -> Void) {
        start(.calibratingHands, engine: nil) { frame, _ in handler(frame) }
    }

    /// Turns hand gestures on with `calibration`, or off with `nil`. Turning them off
    /// cancels a grab in progress. With `aim`, gestures go to the display the hand is held
    /// towards.
    func setGestures(_ calibration: HandCalibration?, aim: HandAim? = nil) {
        self.aim = calibration == nil ? nil : aim
        if let calibration {
            if grab == nil {
                grab = GrabDetector(calibration: calibration)
            } else {
                grab?.calibration = calibration
            }
        } else if let current = grab {
            grab = nil
            faced.removeAll()
            if current.phase == .holding {
                onGesture?(.cancelled)
            }
        }
        updateWantsHands()
    }

    private func updateWantsHands() {
        camera.setWantsHands(mode == .calibratingHands || (mode == .following && grab != nil))
    }

    /// Turns the camera off.
    func stop() {
        generation += 1
        followed = nil
        guard mode != .idle else { return }
        if grab?.phase == .holding {
            onGesture?(.cancelled)
        }
        grab?.reset()
        faced.removeAll()
        aimed.removeAll()
        userFace = nil
        userHand = nil
        lastUserHand = nil
        camera.setHandArea(nil)
        camera.stop()
        typing.stop()
        mode = .idle
        engine = nil
        frameHandler = nil
        failureHandler = nil
        focusedDisplay = nil
        output = nil
        diagnostics = Diagnostics()
        frameTimes.removeAll()
    }

    /// Forgets a camera failure, so the next start tries the camera again.
    func clearCameraFailure() {
        cameraFailure = nil
    }

    private func start(_ mode: Mode, engine: GazeEngine?, handler: ((Frame, GazeEngine.Output?) -> Void)?) {
        generation += 1
        let generation = generation
        self.mode = mode
        self.engine = engine
        frameHandler = handler
        output = nil
        cameraFailure = nil
        camera.setWantsSignatures(mode == .enrolling || engine?.needsSignatures(at: 0) == true)
        updateWantsHands()

        Task {
            do {
                try await camera.start(
                    onFrame: { [weak self] frame in
                        Task { @MainActor in self?.handle(frame) }
                    },
                    onStop: { [weak self] failure in
                        Task { @MainActor in self?.cameraStopped(failure, generation: generation) }
                    })
                // If Glazer was stopped while the camera was starting, stop it now. If another
                // start has happened since, leave the camera to it.
                if generation != self.generation, mode == .idle { camera.stop() }
            } catch {
                let failure = error as? CameraFeed.Failure ?? .cannotOpenCamera
                Logger.app.error("Camera failed to start: \(String(describing: failure))")
                cameraStopped(failure, generation: generation)
            }
        }
    }

    private func cameraStopped(_ failure: CameraFeed.Failure, generation: Int) {
        guard generation == self.generation else { return }
        let handler = failureHandler
        stop()
        cameraFailure = failure
        handler?(failure)
    }

    /// Restarts the typing monitor, such as after Accessibility is granted: macOS only
    /// delivers other apps' key presses to a monitor added while Glazer is trusted.
    func restartTypingMonitor() {
        guard mode == .following else { return }
        typing.start { [weak self] timestamp in
            self?.typingGuard.keyPressed(at: timestamp)
        }
    }

    // MARK: Frames

    private func handle(_ frame: Frame) {
        guard mode != .idle else { return }

        let output = engine?.process(frame)
        self.output = output
        // During hand calibration there's no engine: the user is the nearest face.
        trackUserHand(in: frame, face: mode == .calibratingHands ? frame.nearestFace?.bounds : output?.userFace)
        updateDiagnostics(with: frame)

        if let engine {
            camera.setWantsSignatures(mode == .enrolling || engine.needsSignatures(at: frame.timestamp + 0.1))
        }

        if mode == .following, let output {
            followPointer(output)
            moveFocus(output)
            watchHand(in: frame, output: output)
        }

        frameHandler?(frame, output)
    }

    /// Finds the user's hand, beside their face, and points the camera's hand search at
    /// the area around them.
    private func trackUserHand(in frame: Frame, face: CGRect?) {
        if let face {
            userFace = (face, frame.timestamp)
        } else if let last = userFace, frame.timestamp - last.time > 2 {
            userFace = nil
        }
        aspectRatio = frame.aspectRatio
        var hand = userFace.flatMap { UserHand.hand(of: $0.bounds, among: frame.hands, aspectRatio: aspectRatio) }
        handSource = hand == nil ? "none" : "beside the face"
        // Turning far towards another display can lose the face, or put the hand where it
        // wouldn't be beside a face looking ahead. A grab is already the user's own hand,
        // so while it's held, keep following that hand from frame to frame.
        if hand == nil, grab?.phase == .holding, let last = lastUserHand, frame.timestamp - last.time < 1 {
            hand = UserHand.hand(continuing: last.hand, among: frame.hands)
            if hand != nil { handSource = "followed from the last frame" }
        }
        userHand = hand
        if let hand {
            lastUserHand = (hand, frame.timestamp)
        }
        // Around the face, or the whole image when it's gone, so a held hand isn't lost.
        camera.setHandArea(userFace.map { UserHand.searchArea(around: $0.bounds, aspectRatio: aspectRatio) })
    }

    /// Turns a grab or drop into a ``Gesture`` for the display the hand was held towards
    /// as it began, or else the display the user faced.
    private func watchHand(in frame: Frame, output: GazeEngine.Output) {
        guard grab != nil else { return }
        faced.record(output.facingDisplay ?? output.focusedDisplay, at: frame.timestamp)
        aimed.record(currentAim, at: frame.timestamp)
        let event = grab?.update(userHand, at: frame.timestamp)
        logHeldHand(in: frame, face: output.userFace != nil)
        guard let event else { return }

        let gesture: Gesture? =
            switch event {
            case .grabbed(let startedAt):
                target(at: startedAt).map(Gesture.grabbed)
            case .dropped(let startedAt):
                target(at: startedAt).map(Gesture.dropped)
            case .cancelled:
                .cancelled
            }
        if let gesture {
            onGesture?(gesture)
        } else if case .grabbed = event {
            // No display known for a grab: nothing can be taken, so don't hold one.
            grab?.reset()
        } else {
            onGesture?(.cancelled)
        }
    }

    /// Once a second while a grab is held, what the camera sees of the hand, so a drop that
    /// doesn't happen can be explained from the log.
    private func logHeldHand(in frame: Frame, face: Bool) {
        guard grab?.phase == .holding, frame.timestamp - lastHoldLog >= 1 else { return }
        lastHoldLog = frame.timestamp
        let openness = grab?.openness.map { String(format: "%.2f", $0) } ?? "no hand"
        Logger.app.notice(
            "Holding: openness \(openness, privacy: .public), hand \(self.handSource, privacy: .public), face \(face ? "seen" : "not seen", privacy: .public), \(frame.hands.count, privacy: .public) hands in view"
        )
    }

    /// The display a gesture that began at `timestamp` is for.
    private func target(at timestamp: TimeInterval) -> Display.ID? {
        aimed.display(near: timestamp, within: 0.6) ?? faced.display(at: timestamp) ?? focusedDisplay
    }

    /// The display the user's hand is held towards now, when that's clear.
    private var currentAim: Display.ID? {
        guard let aim, let userHand, let face = userFace?.bounds else { return nil }
        return aim.display(for: UserHand.offset(of: userHand, from: face, aspectRatio: aspectRatio))
    }

    /// The user's hand in the latest frame, for hand calibration.
    var currentUserHand: HandReading? {
        userHand
    }

    /// The latest frame's width over its height, for hand calibration.
    var currentAspectRatio: Double {
        aspectRatio
    }

    /// Where the user's face was last seen, for hand calibration.
    var currentUserFace: CGRect? {
        userFace?.bounds
    }

    /// Keeps the engine in step when the user moves the pointer to another display by
    /// hand, so Glazer doesn't pull it straight back.
    private func followPointer(_ output: GazeEngine.Output) {
        let current = Self.displayUnderPointer(in: displays)
        guard let current, current != pointerDisplay else { return }
        pointerDisplay = current
        focusedDisplay = current
        engine?.userFocused(current)
        typingGuard.userFocused(current)
    }

    /// Moves focus to `target` because the user asked to, such as with the switch key.
    /// Focus stays there until the user turns their head to another display.
    @discardableResult
    func switchManually(to target: Display.ID) -> Bool {
        guard focus.focus(target, leaving: pointerDisplay) else { return false }
        pointerDisplay = target
        focusedDisplay = target
        engine?.userFocused(target)
        typingGuard.userFocused(target)
        return true
    }

    /// Moves focus to the display the user faces, once they aren't typing.
    private func moveFocus(_ output: GazeEngine.Output) {
        let now = ProcessInfo.processInfo.systemUptime
        if isTypingSecurely(at: now) {
            typingGuard.keyPressed(at: now)
        }
        let target =
            if let faced = output.switchedTo {
                typingGuard.userFaces(faced, at: now)
            } else {
                typingGuard.release(at: now, facing: output.facingDisplay)
            }
        guard let target else { return }
        if focus.focus(target, leaving: pointerDisplay) {
            pointerDisplay = target
            focusedDisplay = target
        } else {
            // Focus couldn't move, such as during a drag. Undo the decision, so the switch
            // happens normally once the user faces that display again after letting go.
            engine?.setFocusedDisplay(pointerDisplay)
            if let pointerDisplay { typingGuard.userFocused(pointerDisplay) }
        }
    }

    /// Whether the user is probably typing a password: the frontmost app turned Secure
    /// Event Input on within the last 15 seconds. Longer than that, it's more likely an app
    /// that leaves it on, which mustn't stop Glazer for good.
    private func isTypingSecurely(at now: TimeInterval) -> Bool {
        guard let owner = typing.secureInputOwner else {
            secureInputSince = nil
            return false
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard owner == 0 || owner == frontmost else { return false }
        let since = secureInputSince ?? now
        secureInputSince = since
        return now - since < 15
    }

    private func updateDiagnostics(with frame: Frame) {
        frameTimes.append(frame.timestamp)
        frameTimes.removeAll { frame.timestamp - $0 > 1 }

        let nearest = frame.faces.max { $0.area < $1.area }
        let score: Double? =
            if let signature = nearest?.signature, let verifier = engine?.tracker.verifier {
                verifier.score(signature)
            } else if nearest == nil {
                nil
            } else {
                // Signatures aren't computed on every frame; keep the last score meanwhile.
                diagnostics.matchScore
            }

        diagnostics = Diagnostics(
            faceCount: frame.faces.count,
            rawPose: nearest?.pose,
            brightness: frame.brightness,
            matchScore: score,
            framesPerSecond: Double(frameTimes.count),
            handOpenness: grab?.openness,
            isHoldingGrab: grab?.phase == .holding,
            handAimedAt: currentAim,
            otherHands: frame.hands.count - (userHand == nil ? 0 : 1)
        )
    }

    private static func displayUnderPointer(in displays: [Display]) -> Display.ID? {
        displays.display(nearest: NSEvent.mouseLocation)?.id
    }
}
