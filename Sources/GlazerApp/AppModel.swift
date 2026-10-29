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
        /// Face lock is set up, but its template couldn't be read from the Keychain, such
        /// as when the user chose Deny. Glazer pauses rather than follow just anyone.
        case faceLockUnavailable
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

    var launchesAtLogin: Bool {
        didSet { LaunchAtLogin.setEnabled(launchesAtLogin) }
    }

    private(set) var hasCompletedSetup: Bool
    private(set) var calibration: Calibration?

    // MARK: Permissions

    private(set) var cameraAccess = CameraAccess.current
    private(set) var hasAccessibilityAccess = AccessibilityAccess.isGranted

    // MARK: Face lock

    enum FaceLockState: Equatable {
        case off
        /// A template is in the Keychain but hasn't been read yet. Reading it may make
        /// macOS ask the user, so it waits until face lock is actually needed.
        case stored
        /// The template, held in memory while Glazer runs. The only stored copy is in the
        /// Keychain.
        case ready(FaceTemplate)
        /// The template couldn't be read, such as when the user chose Deny.
        case unreadable
        /// The template came from an older version of Glazer and must be set up again.
        case needsReenrolment
    }

    private(set) var faceLock: FaceLockState = .off

    var isFaceLockOn: Bool {
        faceLock != .off
    }

    var faceTemplate: FaceTemplate? {
        if case .ready(let template) = faceLock { template } else { nil }
    }

    // MARK: Parts

    let displayMonitor = DisplayMonitor()
    let gaze = GazeController()
    let toggleShortcut = KeyboardShortcut.toggle

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let vault: FaceVault
    @ObservationIgnored private var toggleHotKey: HotKey?
    @ObservationIgnored private var session: SessionMonitor?
    @ObservationIgnored private lazy var calibrationCoordinator = CalibrationCoordinator(gaze: gaze)
    private var isCalibrating = false

    init(preferences: Preferences = Preferences(), vault: FaceVault = FaceVault()) {
        self.preferences = preferences
        self.vault = vault
        isEnabled = preferences.isEnabled
        switchDelay = preferences.switchDelay
        hasCompletedSetup = preferences.hasCompletedSetup
        calibration = preferences.calibration
        launchesAtLogin = LaunchAtLogin.isEnabled

        // Only whether a template exists: that never makes macOS ask for the Keychain.
        faceLock = vault.hasTemplate ? .stored : .off
        registerToggleShortcut()
        observeDisplays()
        session = SessionMonitor { [weak self] in self?.refresh() }
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
        if faceLock == .unreadable { return .faceLockUnavailable }
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
        loadFaceTemplateIfNeeded()
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
        faceLock = .ready(template)
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
            Logger.app.error("Could not delete the face template: \(String(describing: error), privacy: .public)")
            return false
        }
        faceLock = .off
        refresh()
        return true
    }

    // MARK: Running

    private var verifier: IdentityVerifier? {
        faceTemplate.map { IdentityVerifier(template: $0) }
    }

    /// Reads the face lock template from the Keychain once it's needed, at most once per
    /// launch. ``retryFaceLock()`` tries again.
    private func loadFaceTemplateIfNeeded() {
        guard faceLock == .stored else { return }
        do {
            if let template = try vault.load() {
                faceLock = template.isCurrent ? .ready(template) : .needsReenrolment
            } else {
                faceLock = .off
            }
        } catch {
            Logger.app.error("Could not read the face template: \(String(describing: error), privacy: .public)")
            faceLock = .unreadable
        }
    }

    /// Tries reading the face lock template again, after it couldn't be read.
    func retryFaceLock() {
        if faceLock == .unreadable {
            faceLock = .stored
        }
        refresh()
    }

    /// Starts, updates or stops following to match the current state.
    ///
    /// It runs after anything that could change the answer: a setting, a permission, the
    /// displays, the screen locking or waking, a camera being connected. Each run also
    /// retries a camera that failed before.
    private func refresh() {
        guard !isCalibrating, gaze.mode != .enrolling else { return }
        gaze.clearCameraFailure()

        // Nobody is at the Mac: the screen is locked or asleep, or another user is in front.
        if session?.isActive == false {
            gaze.stop()
            return
        }

        if isEnabled, attention == nil, calibration != nil {
            loadFaceTemplateIfNeeded()
        }
        if isEnabled, attention == nil, let calibration {
            gaze.follow(displays: displays, calibration: calibration, verifier: verifier, switchDelay: switchDelay)
        } else {
            gaze.stop()
        }
    }

    private func observeDisplays() {
        withObservationTracking {
            _ = displayMonitor.displays
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
