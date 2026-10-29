import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// The app's state, shared by the menu bar, the windows and the overlays.
///
/// It decides when the camera runs: only while Glazer is on, set up, allowed to use the
/// camera, and calibrated for at least two connected displays. The rest of the time the
/// camera is off.
@MainActor
@Observable
final class AppModel {
    /// What Glazer is doing, or what it needs, for the menu bar and the panel.
    enum Condition: Equatable {
        case off
        case attention(Attention)
        case calibrating
        case enrollingFace
        case running(GazeEngine.Status)
    }

    /// Something that stops Glazer from following, and what the user can do about it.
    enum Attention: Equatable {
        case setupNeeded
        case cameraDenied
        case cameraUnavailable
        case secondDisplayNeeded
        case calibrationNeeded
    }

    // MARK: Settings

    /// Whether Glazer is on. Persists between launches.
    var isEnabled: Bool {
        didSet {
            preferences.isEnabled = isEnabled
            refresh()
        }
    }

    /// How long the user must face another display before focus moves, in seconds.
    var switchDelay: Double {
        didSet {
            preferences.switchDelay = switchDelay
            refresh()
        }
    }

    /// When keyboard focus follows the user's gaze.
    var switchMode: SwitchMode {
        didSet {
            preferences.switchMode = switchMode
            refresh()
        }
    }

    var launchesAtLogin: Bool {
        didSet { LaunchAtLogin.setEnabled(launchesAtLogin) }
    }

    private(set) var hasCompletedSetup: Bool
    private(set) var calibration: Calibration?

    // MARK: Permissions

    private(set) var cameraAccess = CameraAccess.current
    private(set) var hasAccessibilityAccess = AccessibilityAccess.isGranted

    // MARK: Face lock

    /// The enrolled face, held in memory while Glazer runs. The only stored copy is in
    /// the Keychain.
    private(set) var faceTemplate: FaceTemplate?

    /// Set when the stored template came from an older version of Glazer and must be
    /// enrolled again.
    private(set) var faceLockNeedsReenrolment = false

    var isFaceLockOn: Bool {
        faceTemplate != nil
    }

    // MARK: Parts

    let displayMonitor = DisplayMonitor()
    let gaze = GazeController()
    let toggleShortcut = KeyboardShortcut.toggle

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let vault: FaceVault
    @ObservationIgnored private var toggleHotKey: HotKey?
    @ObservationIgnored private lazy var calibrationCoordinator = CalibrationCoordinator(gaze: gaze)
    private var isCalibrating = false

    init(preferences: Preferences = Preferences(), vault: FaceVault = FaceVault()) {
        self.preferences = preferences
        self.vault = vault
        isEnabled = preferences.isEnabled
        switchDelay = preferences.switchDelay
        switchMode = preferences.switchMode
        hasCompletedSetup = preferences.hasCompletedSetup
        calibration = preferences.calibration
        launchesAtLogin = LaunchAtLogin.isEnabled

        loadFaceTemplate()
        registerToggleShortcut()
        observeDisplays()
        refresh()
    }

    // MARK: Condition

    var condition: Condition {
        if isCalibrating { return .calibrating }
        if gaze.mode == .enrolling { return .enrollingFace }
        if !isEnabled { return .off }
        if let attention { return .attention(attention) }
        return .running(gaze.output?.status ?? .searching)
    }

    private var attention: Attention? {
        if !hasCompletedSetup || cameraAccess == .notDetermined { return .setupNeeded }
        if cameraAccess != .granted { return .cameraDenied }
        if gaze.cameraFailure != nil { return .cameraUnavailable }
        if displays.count < 2 { return .secondDisplayNeeded }
        if calibration?.covers(displays) != true { return .calibrationNeeded }
        return nil
    }

    var displays: [Display] {
        displayMonitor.displays
    }

    /// The display to highlight in the panel: the one Glazer has focused while running,
    /// otherwise the one under the pointer.
    var highlightedDisplay: Display.ID? {
        if case .running = condition, let focused = gaze.output?.focusedDisplay {
            return focused
        }
        return displayMonitor.pointerDisplayID
    }

    var canCalibrate: Bool {
        displays.count >= 2 && cameraAccess == .granted && !isCalibrating && gaze.mode != .enrolling
    }

    // MARK: Actions

    func toggle() {
        isEnabled.toggle()
    }

    /// Re-reads permissions, which have no change notifications.
    func refreshPermissions() {
        let camera = CameraAccess.current
        let accessibility = AccessibilityAccess.isGranted
        guard camera != cameraAccess || accessibility != hasAccessibilityAccess else { return }
        cameraAccess = camera
        hasAccessibilityAccess = accessibility
        refresh()
    }

    func requestCameraAccess() async {
        cameraAccess = await CameraAccess.request()
        refresh()
    }

    func completeSetup() {
        hasCompletedSetup = true
        preferences.hasCompletedSetup = true
        refresh()
    }

    /// Runs calibration on every display. `completion` reports whether it finished.
    func calibrate(completion: ((Bool) -> Void)? = nil) {
        guard canCalibrate else {
            completion?(false)
            return
        }
        gaze.stop()
        isCalibrating = true
        calibrationCoordinator.start(displays: displays, verifier: verifier) { [weak self] calibration in
            guard let self else { return }
            isCalibrating = false
            if let calibration {
                self.calibration = calibration
                preferences.calibration = calibration
            }
            refresh()
            completion?(calibration != nil)
        }
    }

    // MARK: Face lock

    /// Starts the camera for face lock enrolment. Call ``finishFaceEnrolment(with:)`` or
    /// ``cancelFaceEnrolment()`` to end it.
    func beginFaceEnrolment(onFrame: @escaping (Frame) -> Void) {
        gaze.stop()
        gaze.enroll { frame, _ in onFrame(frame) }
    }

    /// Saves `template` to the Keychain and turns face lock on.
    func finishFaceEnrolment(with template: FaceTemplate) throws {
        gaze.stop()
        try vault.save(template)
        faceTemplate = template
        faceLockNeedsReenrolment = false
        refresh()
    }

    func cancelFaceEnrolment() {
        gaze.stop()
        refresh()
    }

    /// Deletes the enrolled face after the owner confirms with Touch ID or their
    /// password. Returns whether it was deleted.
    func deleteFaceLock() async -> Bool {
        guard await OwnerAuthentication.confirm(reason: "delete your face from face lock") else { return false }
        do {
            try vault.delete()
        } catch {
            Logger.app.error("Could not delete the face template: \(error)")
            return false
        }
        faceTemplate = nil
        refresh()
        return true
    }

    // MARK: Running

    private var verifier: IdentityVerifier? {
        faceTemplate.map { IdentityVerifier(template: $0) }
    }

    /// Starts, updates or stops following to match the current state.
    private func refresh() {
        guard !isCalibrating, gaze.mode != .enrolling else { return }

        if isEnabled, attention == nil, let calibration {
            gaze.follow(
                displays: displays, calibration: calibration, verifier: verifier, switchDelay: switchDelay,
                switchMode: switchMode)
        } else {
            gaze.stop()
        }
    }

    private func loadFaceTemplate() {
        do {
            guard let template = try vault.load() else { return }
            if template.isCurrent {
                faceTemplate = template
            } else {
                faceLockNeedsReenrolment = true
            }
        } catch {
            Logger.app.error("Could not read the face template: \(error)")
        }
    }

    private func observeDisplays() {
        withObservationTracking {
            _ = displayMonitor.displays
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.gaze.updateDisplays(self.displays)
                self.refresh()
                self.observeDisplays()
            }
        }
    }

    private func registerToggleShortcut() {
        do {
            toggleHotKey = try HotKey(toggleShortcut) { [weak self] in
                self?.toggle()
            }
        } catch {
            // Another app may own the shortcut. Glazer still works from the menu bar.
            Logger.app.error("Could not register \(self.toggleShortcut.displayString): \(error)")
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "app")
}
