import AppKit
import GlazerCore
import Observation

/// Drives hand calibration: record the user's open hand and fist, then where they hold
/// their hand for each display, then let them try grabs and drops before saving.
@MainActor
@Observable
final class HandCalibrationFlow {
    enum Step: Equatable {
        case intro
        /// Recording the open hand and the fist.
        case shapes
        /// Recording where the hand is held for each display.
        case aiming
        case trying
        case failed(HandCalibration.Problem)
    }

    private(set) var step: Step = .intro
    private(set) var shapes = HandCalibrationRecorder()
    private(set) var aiming: HandAimRecorder?
    /// Whether the hand position told the displays apart. When it didn't, gestures go to
    /// the display the user faces.
    private(set) var aim: HandAim?
    private(set) var aimProblem: HandAim.Problem?
    /// Grabs and drops recognised while trying.
    private(set) var grabs = 0
    private(set) var drops = 0
    private(set) var isHolding = false
    /// How open the hand is while trying, from 0 (fist) to 1 (open), or `nil` with no hand.
    private(set) var openness: Double?
    /// The display the hand is held towards while trying, when that's clear.
    private(set) var aimedAt: Display.ID?
    private(set) var seesFace = false
    private(set) var seesHand = false

    private let model: AppModel
    private let prompt = AimPromptOverlay()
    private var calibration: HandCalibration?
    private var tester: GrabDetector?

    init(model: AppModel) {
        self.model = model
    }

    /// The displays, in the order the user is asked to hold their hand towards them.
    var displays: [Display] {
        model.displays.inReadingOrder
    }

    func start() {
        shapes = HandCalibrationRecorder()
        aiming = nil
        aim = nil
        aimProblem = nil
        calibration = nil
        tester = nil
        grabs = 0
        drops = 0
        isHolding = false
        openness = nil
        step = .shapes
        model.beginHandCalibration { [weak self] frame in
            self?.add(frame)
        }
    }

    /// Saves the calibration and turns the camera back over to following.
    func save() {
        guard let calibration else { return }
        prompt.hide()
        model.finishHandCalibration(with: calibration, aim: aim)
        step = .intro
    }

    func cancel() {
        prompt.hide()
        if step == .shapes || step == .aiming || step == .trying {
            model.cancelHandCalibration()
        }
        step = .intro
    }

    private func add(_ frame: Frame) {
        let hand = model.gaze.currentUserHand
        let face = model.gaze.currentUserFace
        seesFace = face != nil
        seesHand = hand != nil
        switch step {
        case .shapes: addShape(hand, at: frame.timestamp)
        case .aiming: addAim(hand, face: face, at: frame.timestamp)
        case .trying: addTrial(hand, face: face, at: frame.timestamp)
        case .intro, .failed: break
        }
    }

    private func addShape(_ hand: HandReading?, at timestamp: TimeInterval) {
        switch shapes.add(hand, at: timestamp) {
        case .finished(let calibration):
            self.calibration = calibration
            if displays.count >= 2 {
                aiming = HandAimRecorder(displays: displays.map(\.id), calibration: calibration)
                step = .aiming
                showPrompt()
            } else {
                startTrying()
            }
        case .failed(let problem):
            model.cancelHandCalibration()
            step = .failed(problem)
        case .waiting, .recording:
            break
        }
    }

    private func addAim(_ hand: HandReading?, face: CGRect?, at timestamp: TimeInterval) {
        guard var aiming else { return }
        let progress = aiming.add(hand: hand, face: face, at: timestamp)
        self.aiming = aiming
        switch progress {
        case .finished(let aim):
            self.aim = aim
            startTrying()
        case .failed(let problem):
            // Not a failure of calibration: gestures go to where the user looks instead.
            aimProblem = problem
            startTrying()
        case .waiting, .recording:
            showPrompt()
        }
    }

    private func addTrial(_ hand: HandReading?, face: CGRect?, at timestamp: TimeInterval) {
        let event = tester?.update(hand, at: timestamp)
        openness = tester?.openness
        aimedAt = aim.flatMap { aim in
            guard let hand, let face else { return nil }
            return aim.display(for: UserHand.offset(of: hand, from: face))
        }
        switch event {
        case .grabbed:
            grabs += 1
            isHolding = true
        case .dropped:
            drops += 1
            isHolding = false
        case .cancelled:
            isHolding = false
        case nil:
            break
        }
    }

    private func startTrying() {
        prompt.hide()
        tester = calibration.map { GrabDetector(calibration: $0) }
        step = .trying
    }

    /// Shows the prompt on the display the hand should be held towards now.
    private func showPrompt() {
        guard let aiming, aiming.step < aiming.displays.count else { return }
        let id = aiming.displays[aiming.step]
        guard let display = displays.first(where: { $0.id == id }) else { return }
        let fraction: Double? =
            if case .recording(_, let fraction) = aiming.progress { fraction } else { nil }
        prompt.show(on: display, number: aiming.step + 1, of: aiming.displays.count, recording: fraction)
    }
}
