import GlazerCore
import Observation

/// Drives hand calibration: record the user's open hand and fist, let them try a grab
/// and a drop with the result, then save it.
@MainActor
@Observable
final class HandCalibrationFlow {
    enum Step: Equatable {
        case intro
        case recording
        case trying
        case failed(HandCalibration.Problem)
    }

    /// How far the user has got trying the new calibration.
    enum Trial: Equatable {
        case waitingForGrab
        case holding
        case dropped
    }

    private(set) var step: Step = .intro
    private(set) var recorder = HandCalibrationRecorder()
    private(set) var trial: Trial = .waitingForGrab
    /// How open the hand is while trying, from 0 (fist) to 1 (open), or `nil` with no hand.
    private(set) var openness: Double?
    /// Whether a hand is in view in the latest frame.
    private(set) var seesHand = false

    private let model: AppModel
    private var calibration: HandCalibration?
    private var tester: GrabDetector?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        recorder = HandCalibrationRecorder()
        calibration = nil
        tester = nil
        trial = .waitingForGrab
        openness = nil
        step = .recording
        model.beginHandCalibration { [weak self] frame in
            self?.add(frame)
        }
    }

    /// Saves the calibration and turns the camera back over to following.
    func save() {
        guard let calibration else { return }
        model.finishHandCalibration(with: calibration)
        step = .intro
    }

    func cancel() {
        if step == .recording || step == .trying {
            model.cancelHandCalibration()
        }
        step = .intro
    }

    private func add(_ frame: Frame) {
        seesHand = frame.hand != nil
        switch step {
        case .recording:
            switch recorder.add(frame.hand, at: frame.timestamp) {
            case .finished(let calibration):
                self.calibration = calibration
                tester = GrabDetector(calibration: calibration)
                step = .trying
            case .failed(let problem):
                model.cancelHandCalibration()
                step = .failed(problem)
            case .waiting, .recording:
                break
            }
        case .trying:
            let event = tester?.update(frame.hand, at: frame.timestamp)
            openness = tester?.openness
            switch event {
            case .grabbed: trial = .holding
            case .dropped: trial = .dropped
            case .cancelled: trial = .waitingForGrab
            case nil: break
            }
        case .intro, .failed:
            break
        }
    }
}
