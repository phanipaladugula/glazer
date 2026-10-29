import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// Drives face lock setup: confirm the owner, scan the face, save it to the Keychain.
@MainActor
@Observable
final class FaceEnrolmentFlow {
    enum Step: Equatable {
        case intro
        case scanning
        case saved
        case failed(String)
    }

    private(set) var step: Step = .intro
    private(set) var enrolment = FaceEnrollment()

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Asks for Touch ID or the password, then starts scanning.
    func start() async {
        guard await OwnerAuthentication.confirm(reason: "set up face lock") else { return }
        enrolment = FaceEnrollment()
        step = .scanning
        model.beginFaceEnrolment { [weak self] frame in
            self?.add(frame)
        }
    }

    func cancel() {
        if step == .scanning {
            model.cancelFaceEnrolment()
        }
        step = .intro
    }

    private func add(_ frame: Frame) {
        guard step == .scanning else { return }
        enrolment.add(frame)
        guard let template = enrolment.template else { return }

        do {
            try model.finishFaceEnrolment(with: template)
            step = .saved
        } catch {
            Logger.app.error("Could not save the face template: \(error)")
            model.cancelFaceEnrolment()
            step = .failed("Glazer couldn't save your face to the Keychain. Nothing was stored.")
        }
    }
}
