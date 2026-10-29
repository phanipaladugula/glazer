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

    /// Set when the camera couldn't start.
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

    // MARK: Modes

    /// Follows the user and moves focus between `displays`.
    func follow(displays: [Display], calibration: Calibration, verifier: IdentityVerifier?, switchDelay: Double) {
        var classification = DisplayClassifier.Configuration()
        classification.dwell = switchDelay
        var engine = GazeEngine(calibration: calibration, verifier: verifier, classification: classification)

        self.displays = displays
        pointerDisplay = Self.displayUnderPointer(in: displays)
        engine.setFocusedDisplay(pointerDisplay)
        typingGuard = TypingGuard(focusedDisplay: pointerDisplay)
        typing.start { [weak self] timestamp in
            self?.typingGuard.keyPressed(at: timestamp)
        }
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
        typing.stop()
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
        if current != output.focusedDisplay {
            engine?.setFocusedDisplay(current)
            typingGuard.userFocused(current)
        }
    }

    /// Moves focus to the display the user faces, once they aren't typing.
    private func moveFocus(_ output: GazeEngine.Output) {
        let now = ProcessInfo.processInfo.systemUptime
        let target =
            if let faced = output.switchedTo {
                typingGuard.userFaces(faced, at: now)
            } else {
                typingGuard.release(at: now)
            }
        guard let target else { return }
        focus.focus(target, leaving: pointerDisplay)
        pointerDisplay = target
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
