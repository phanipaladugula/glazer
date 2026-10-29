import AppKit
import GlazerCore
import GlazerSystem
import OSLog
import Observation

/// The app's state, shared by the menu bar, the windows and the overlays.
///
/// It decides when the camera runs: only while Glazer is on, set up to switch with the
/// camera, allowed to use it, and calibrated for at least two connected displays. The rest
/// of the time the camera is off. It also decides when the switch key is listened for.
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
        /// Switching by shortcut only: waiting for the user to press it.
        case listening(KeyboardShortcut)
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
        /// Without Accessibility, Glazer can move the pointer but not the keyboard, which
        /// sends typing to the display the user isn't looking at. So it pauses instead.
        case accessibilityNeeded
        /// Switching by shortcut only, and macOS or another app already uses the shortcut.
        case shortcutUnavailable
    }

    // MARK: Settings

    /// Whether Glazer is on. Persists between launches.
    var isEnabled: Bool {
        didSet {
            preferences.isEnabled = isEnabled
            refresh()
        }
    }

    /// Whether displays switch by the camera, by double-pressing a key, or both.
    var switchingMethod: SwitchingMethod {
        didSet {
            preferences.switchingMethod = switchingMethod
            refresh()
        }
    }

    /// The shortcut that moves to the next display.
    var switchShortcut: KeyboardShortcut {
        didSet {
            preferences.switchShortcut = switchShortcut
            refresh()
        }
    }

    /// Why the switch shortcut couldn't be registered, such as macOS or another app using
    /// it. `nil` when it's registered, or not needed.
    private(set) var switchShortcutError: HotKey.Error?

    /// While the user records a new shortcut, the current one is released, so pressing it
    /// reaches the recorder instead of switching displays.
    var isRecordingShortcut = false {
        didSet { refresh() }
    }

    /// How long the user must face another display before focus moves, in seconds.
    var switchDelay: Double {
        didSet {
            preferences.switchDelay = switchDelay
            refresh()
        }
    }

    /// Whether hand gestures take and drop screenshots. Turning them on asks for Screen
    /// Recording permission if Glazer doesn't have it yet.
    var gesturesEnabled: Bool {
        didSet {
            preferences.gesturesEnabled = gesturesEnabled
            if gesturesEnabled, !hasScreenCaptureAccess {
                ScreenCaptureAccess.request()
            }
            refresh()
        }
    }

    /// The user's open hand and fist, as the camera sees them.
    private(set) var handCalibration: HandCalibration?

    /// Where the user holds their hand for each display, when calibration could tell the
    /// displays apart that way. Without it, gestures go to the display the user faces.
    private(set) var handAim: HandAim?

    /// Whether gestures choose a display by where the hand is held, for the connected
    /// displays.
    var aimsWithHand: Bool {
        handAim?.covers(displays) == true
    }

    /// Why gestures that are on can't work yet, or `nil` when they can or are off.
    var gestureIssue: GestureIssue? {
        guard gesturesEnabled else { return nil }
        if !switchingMethod.usesCamera { return .needsCamera }
        if handCalibration == nil { return .needsHandCalibration }
        if !hasScreenCaptureAccess { return .needsScreenRecording }
        return nil
    }

    enum GestureIssue: Equatable {
        /// Gestures are seen by the camera, which isn't used when switching by shortcut only.
        case needsCamera
        case needsHandCalibration
        case needsScreenRecording
    }

    /// Whether Glazer opens at login. Reads back what macOS actually did, so the switch
    /// never shows on when registering failed.
    var launchesAtLogin: Bool {
        get { launchAtLoginEnabled }
        set {
            LaunchAtLogin.setEnabled(newValue)
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
        }
    }
    private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    /// macOS registered the login item but wants the user to approve it in System Settings.
    private(set) var launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval

    private(set) var hasCompletedSetup: Bool
    private(set) var calibration: Calibration?

    // MARK: Permissions

    private(set) var cameraAccess = CameraAccess.current
    private(set) var hasAccessibilityAccess = AccessibilityAccess.isGranted
    private(set) var hasScreenCaptureAccess = ScreenCaptureAccess.isGranted

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
    let gaze: GazeController
    let toggleShortcut = KeyboardShortcut.toggle

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let vault: FaceVault
    /// Moves the pointer and keyboard. Shared by the camera and the switch key, so both
    /// remember the same pointer position on each display.
    @ObservationIgnored private let focus: FocusController
    @ObservationIgnored private var switchHotKey: HotKey?
    /// The shortcut ``switchHotKey`` was registered for.
    @ObservationIgnored private var registeredShortcut: KeyboardShortcut?
    @ObservationIgnored private var toggleHotKey: HotKey?
    @ObservationIgnored private var session: SessionMonitor?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private lazy var calibrationCoordinator = CalibrationCoordinator(gaze: gaze)
    @ObservationIgnored private let grabs = GrabController()
    private var isCalibrating = false

    init(preferences: Preferences = Preferences(), vault: FaceVault = FaceVault()) {
        self.preferences = preferences
        self.vault = vault
        let focus = FocusController()
        self.focus = focus
        gaze = GazeController(focus: focus)
        isEnabled = preferences.isEnabled
        switchingMethod = preferences.switchingMethod
        switchShortcut = preferences.switchShortcut
        switchDelay = preferences.switchDelay
        hasCompletedSetup = preferences.hasCompletedSetup
        calibration = preferences.calibration
        gesturesEnabled = preferences.gesturesEnabled
        handCalibration = preferences.handCalibration
        handAim = preferences.handAim

        // Only whether a template exists: that never makes macOS ask for the Keychain.
        faceLock = vault.hasTemplate ? .stored : .off
        gaze.onGesture = { [weak self] gesture in self?.grabs.handle(gesture) }
        registerToggleShortcut()
        observeDisplays()
        observeFacedDisplay()
        session = SessionMonitor { [weak self] in self?.refresh() }
        watchPermissions()
        refresh()
    }

    /// Permissions have no change notifications, and Accessibility can stop working
    /// without the user touching it (after an update, macOS may keep the switch on in
    /// System Settings while no longer trusting the new build). Both checks are cheap, so
    /// they run every couple of seconds; nothing happens unless one changes.
    private func watchPermissions() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    // MARK: Condition

    var condition: Condition {
        if isCalibrating || gaze.mode == .calibratingHands { return .calibrating }
        if gaze.mode == .enrolling { return .enrollingFace }
        if !isEnabled { return .off }
        if let attention { return .attention(attention) }
        if !switchingMethod.usesCamera { return .listening(switchShortcut) }
        return .running(gaze.output?.status ?? .searching)
    }

    /// The first thing stopping Glazer. The camera's needs count only when it switches
    /// with the camera.
    private var attention: Attention? {
        let usesCamera = switchingMethod.usesCamera
        if !hasCompletedSetup || (usesCamera && cameraAccess == .notDetermined) { return .setupNeeded }
        if usesCamera, cameraAccess != .granted { return .cameraDenied }
        if usesCamera, gaze.cameraFailure != nil { return .cameraUnavailable }
        if displays.count < 2 { return .secondDisplayNeeded }
        if usesCamera, calibration?.covers(displays) != true { return .calibrationNeeded }
        if usesCamera, faceLock == .unreadable { return .faceLockUnavailable }
        if !hasAccessibilityAccess { return .accessibilityNeeded }
        if !usesCamera, switchShortcutError != nil { return .shortcutUnavailable }
        return nil
    }

    /// Whether the switch shortcut is registered. It doesn't wait on the camera: in
    /// ``SwitchingMethod/both`` the shortcut keeps working while the camera can't.
    private var shouldRegisterShortcut: Bool {
        isEnabled && hasCompletedSetup && switchingMethod.usesShortcut && hasAccessibilityAccess
            && displays.count >= 2 && !isCalibrating && !isRecordingShortcut && session?.isActive != false
    }

    var displays: [Display] {
        displayMonitor.displays
    }

    /// The display to highlight in the panel: the one Glazer has focused while running,
    /// otherwise the one under the pointer.
    var highlightedDisplay: Display.ID? {
        if case .running = condition, let focused = gaze.focusedDisplay {
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
        let screenCapture = ScreenCaptureAccess.isGranted
        guard
            camera != cameraAccess || accessibility != hasAccessibilityAccess
                || screenCapture != hasScreenCaptureAccess
        else { return }
        let gainedAccessibility = accessibility && !hasAccessibilityAccess
        cameraAccess = camera
        hasAccessibilityAccess = accessibility
        hasScreenCaptureAccess = screenCapture
        refresh()
        if gainedAccessibility {
            gaze.restartTypingMonitor()
        }
    }

    func requestCameraAccess() async {
        cameraAccess = await CameraAccess.request()
        refresh()
    }

    /// Moves the pointer and keyboard to the next display, in reading order. The switch
    /// shortcut calls it.
    func switchToNextDisplay() {
        let current = gaze.focusedDisplay ?? displayMonitor.pointerDisplayID
        guard let target = displays.display(after: current)?.id else { return }
        if gaze.mode == .following {
            // The engine learns the user moved focus themselves, so it doesn't pull focus
            // straight back to the display they face.
            gaze.switchManually(to: target)
        } else {
            _ = focus.focus(target, leaving: current)
        }
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
        unregisterShortcut()
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

    // MARK: Hand gestures

    /// Starts the camera for hand calibration. Call ``finishHandCalibration(with:)`` or
    /// ``cancelHandCalibration()`` to end it.
    func beginHandCalibration(onFrame: @escaping (Frame) -> Void) {
        gaze.stop()
        gaze.calibrateHands(handler: onFrame)
    }

    func finishHandCalibration(with calibration: HandCalibration, aim: HandAim?) {
        gaze.stop()
        handCalibration = calibration
        preferences.handCalibration = calibration
        handAim = aim
        preferences.handAim = aim
        refresh()
    }

    func cancelHandCalibration() {
        gaze.stop()
        refresh()
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

    /// Tries the camera again after it failed or stopped.
    func retryCamera() {
        refresh()
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
        guard !isCalibrating, gaze.mode != .enrolling, gaze.mode != .calibratingHands else { return }
        updateShortcut()
        gaze.clearCameraFailure()

        // Nobody is at the Mac: the screen is locked or asleep, or another user is in front.
        if session?.isActive == false {
            gaze.stop()
            return
        }

        let followsWithCamera = isEnabled && switchingMethod.usesCamera && attention == nil
        if followsWithCamera, calibration != nil {
            loadFaceTemplateIfNeeded()
        }
        gaze.setGestures(
            gestureIssue == nil && gesturesEnabled ? handCalibration : nil, aim: aimsWithHand ? handAim : nil)
        if followsWithCamera, attention == nil, let calibration {
            gaze.follow(displays: displays, calibration: calibration, verifier: verifier, switchDelay: switchDelay)
        } else {
            gaze.stop()
        }
    }

    /// Registers the switch shortcut while it's needed, and releases it otherwise.
    private func updateShortcut() {
        guard shouldRegisterShortcut else {
            unregisterShortcut()
            return
        }
        guard registeredShortcut != switchShortcut else { return }
        unregisterShortcut()
        do {
            // Exclusive: a shortcut macOS or another app also uses would do two things.
            switchHotKey = try HotKey(switchShortcut, exclusive: true) { [weak self] in
                self?.switchToNextDisplay()
            }
            registeredShortcut = switchShortcut
        } catch {
            switchShortcutError = error as? HotKey.Error ?? .registrationFailed(0)
            Logger.app.error("Could not register \(self.switchShortcut.displayString): \(error)")
        }
    }

    private func unregisterShortcut() {
        switchHotKey = nil
        registeredShortcut = nil
        switchShortcutError = nil
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

    /// Keeps a held screenshot's thumbnail on the display the user faces.
    private func observeFacedDisplay() {
        withObservationTracking {
            _ = gaze.focusedDisplay
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                grabs.facingChanged(to: gaze.focusedDisplay)
                observeFacedDisplay()
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
