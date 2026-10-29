import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// Runs the camera and the gaze engine, and moves the pointer and keyboard focus as the
/// ``FocusPolicy`` decides.
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

    /// Set when the camera couldn't start.
    private(set) var cameraFailure: CameraFeed.Failure?

    /// Set when the switch mode needs the keyboard but macOS didn't allow it (no
    /// Accessibility access). Glazer then moves the pointer and focus together.
    private(set) var isKeyboardUnavailable = false

    struct Diagnostics: Equatable {
        var faceCount = 0
        var rawPose: HeadPose?
        var brightness = 0.0
        var matchScore: Double?
        var framesPerSecond = 0.0
    }

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let focus = FocusController()
    @ObservationIgnored private let keyboard = KeyboardMonitor()
    @ObservationIgnored private var policy = FocusPolicy(mode: .immediate, keyboardDisplay: nil)
    @ObservationIgnored private var engine: GazeEngine?
    @ObservationIgnored private var frameHandler: ((Frame, GazeEngine.Output?) -> Void)?
    @ObservationIgnored private var displays: [Display] = []
    @ObservationIgnored private var pointerDisplay: Display.ID?
    @ObservationIgnored private var frameTimes: [TimeInterval] = []

    // MARK: Modes

    /// Follows the user and moves focus between `displays`.
    func follow(
        displays: [Display], calibration: Calibration, verifier: IdentityVerifier?, switchDelay: Double,
        switchMode: SwitchMode
    ) {
        var classification = DisplayClassifier.Configuration()
        classification.dwell = switchDelay
        var engine = GazeEngine(calibration: calibration, verifier: verifier, classification: classification)

        self.displays = displays
        pointerDisplay = Self.displayUnderPointer(in: displays)
        engine.setFocusedDisplay(pointerDisplay)
        startPolicy(switchMode)
        start(.following, engine: engine, handler: nil)
    }

    /// Reports the user's pose to `handler` on every frame, without moving focus.
    func calibrate(verifier: IdentityVerifier?, handler: @escaping (Frame, GazeEngine.Output?) -> Void) {
        start(.calibrating, engine: GazeEngine(calibration: nil, verifier: verifier), handler: handler)
    }

    /// Reports every frame, with signatures for each face, to `handler`.
    func enroll(handler: @escaping (Frame, GazeEngine.Output?) -> Void) {
        start(.enrolling, engine: nil, handler: handler)
    }

    /// Turns the camera off.
    func stop() {
        guard mode != .idle else { return }
        camera.stop()
        keyboard.stop()
        mode = .idle
        engine = nil
        frameHandler = nil
        output = nil
        diagnostics = Diagnostics()
        frameTimes.removeAll()
    }

    /// Updates the displays while following, such as when one is connected.
    func updateDisplays(_ displays: [Display]) {
        self.displays = displays
    }

    private func start(_ mode: Mode, engine: GazeEngine?, handler: ((Frame, GazeEngine.Output?) -> Void)?) {
        self.mode = mode
        self.engine = engine
        frameHandler = handler
        output = nil
        cameraFailure = nil
        camera.setWantsSignatures(mode == .enrolling || engine?.needsSignatures(at: 0) == true)

        Task {
            do {
                try await camera.start { [weak self] frame in
                    Task { @MainActor in self?.handle(frame) }
                }
            } catch let failure as CameraFeed.Failure {
                Logger.app.error("Camera failed to start: \(String(describing: failure))")
                cameraFailure = failure
                stop()
            } catch {
                Logger.app.error("Camera failed to start: \(error)")
                cameraFailure = .cannotOpenCamera
                stop()
            }
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
            if let target = output.switchedTo {
                perform(policy.userFaces(target))
            }
        }

        frameHandler?(frame, output)
    }

    /// Keeps the engine in step when the user moves the pointer to another display by
    /// hand, so Glazer doesn't pull it straight back.
    private func followPointer(_ output: GazeEngine.Output) {
        let current = Self.displayUnderPointer(in: displays)
        guard let current, current != pointerDisplay else { return }
        pointerDisplay = current
        if current != output.focusedDisplay {
            engine?.setFocusedDisplay(current)
            policy.userMovedPointer(to: current)
        }
    }

    // MARK: Focus

    /// Sets up the focus policy, and the keyboard monitor if the mode needs it. Without
    /// Accessibility access there's no keyboard monitor, so Glazer falls back to moving the
    /// pointer and focus together.
    private func startPolicy(_ requested: SwitchMode) {
        var mode = requested
        if FocusPolicy(mode: requested, keyboardDisplay: nil).needsKeyboard {
            keyboard.onKeyDown = { [weak self] timestamp in
                self?.keyPressed(at: timestamp) ?? .deliver
            }
            keyboard.onHoldKeyChange = { [weak self] isDown in
                guard let self else { return }
                perform(policy.holdKeyChanged(isDown: isDown))
            }
            if !keyboard.start() {
                mode = .immediate
            }
        } else {
            keyboard.stop()
        }
        isKeyboardUnavailable = mode != requested
        policy = FocusPolicy(mode: mode, keyboardDisplay: pointerDisplay)
    }

    private func keyPressed(at timestamp: TimeInterval) -> KeyboardMonitor.Disposition {
        let actions = policy.keyPressed(at: timestamp)
        guard !actions.isEmpty else { return .deliver }
        perform(actions)
        return .holdForFocusChange
    }

    private func perform(_ actions: [FocusPolicy.Action]) {
        for action in actions {
            switch action {
            case .movePointer(let display):
                guard display != pointerDisplay else { continue }
                focus.movePointer(to: display, leaving: pointerDisplay)
                pointerDisplay = display
            case .moveKeyboardFocus(let display):
                focus.moveKeyboardFocus(to: display)
            }
        }
    }

    private func updateDiagnostics(with frame: Frame) {
        frameTimes.append(frame.timestamp)
        frameTimes.removeAll { frame.timestamp - $0 > 1 }

        let nearest = frame.faces.max { $0.area < $1.area }
        let score: Double? =
            if let signature = nearest?.signature, let verifier = engine?.tracker.verifier {
                verifier.score(signature)
            } else {
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
        displays.display(containing: NSEvent.mouseLocation)?.id
    }
}
