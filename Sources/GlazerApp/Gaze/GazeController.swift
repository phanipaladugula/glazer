import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// Runs the camera and the gaze engine, and moves focus when the engine decides to and the
/// user isn't typing.
///
/// The camera runs only in one of three modes: following the user, calibrating, or
/// enrolling face lock. Otherwise it is off.
@MainActor
@Observable
final class GazeController {
    enum Mode: Equatable {
        case idle
        case following
        case calibrating
        case enrolling
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
    }

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let focus = FocusController()
    @ObservationIgnored private let typing = TypingMonitor()
    @ObservationIgnored private var typingGuard = TypingGuard(focusedDisplay: nil)
    @ObservationIgnored private var engine: GazeEngine?
    @ObservationIgnored private var frameHandler: ((Frame, GazeEngine.Output?) -> Void)?
    @ObservationIgnored private var displays: [Display] = []
    @ObservationIgnored private var pointerDisplay: Display.ID?
    @ObservationIgnored private var frameTimes: [TimeInterval] = []
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

    /// Turns the camera off.
    func stop() {
        generation += 1
        followed = nil
        guard mode != .idle else { return }
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
        updateDiagnostics(with: frame)

        if let engine {
            camera.setWantsSignatures(mode == .enrolling || engine.needsSignatures(at: frame.timestamp + 0.1))
        }

        if mode == .following, let output {
            followPointer(output)
            moveFocus(output)
        }

        frameHandler?(frame, output)
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
            framesPerSecond: Double(frameTimes.count)
        )
    }

    private static func displayUnderPointer(in displays: [Display]) -> Display.ID? {
        displays.display(nearest: NSEvent.mouseLocation)?.id
    }
}
