import GlazerCore
import GlazerSystem
import SwiftUI

/// Glazer › Settings.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettings(model: model)
                .tabItem { Label("Displays", systemImage: "display.2") }
            FaceLockSettings(model: model)
                .tabItem { Label("Face Lock", systemImage: "faceid") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            DiagnosticsSettings(model: model)
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .frame(width: 520)
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Glazer is on", isOn: $model.isEnabled)
                LabeledContent("Shortcut") {
                    Text(model.toggleShortcut.displayString)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Toggle("Open at login", isOn: $model.launchesAtLogin)
                if model.launchAtLoginNeedsApproval {
                    LabeledContent("Approve Glazer in Login Items to finish") {
                        Button("Open Login Items…") { SystemSettings.open(.loginItems) }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Switch displays by", selection: $model.switchingMethod) {
                    ForEach(SwitchingMethod.allCases, id: \.self) { method in
                        Text(method.title).tag(method)
                    }
                }
                if model.switchingMethod.usesShortcut {
                    LabeledContent("Next display") {
                        ShortcutRecorder(model: model)
                    }
                }
            } footer: {
                if model.switchShortcutError != nil {
                    Text(
                        "Choose another shortcut, or turn off the one macOS uses in System Settings › Keyboard › "
                            + "Keyboard Shortcuts.")
                } else {
                    Text(model.switchingMethod.detail)
                }
            }

            if model.switchingMethod.usesCamera {
                switchDelaySection
            }

            Section("Permissions") {
                if model.switchingMethod.usesCamera {
                    PermissionRow(
                        title: "Camera",
                        isGranted: model.cameraAccess == .granted,
                        action: { SystemSettings.open(.camera) }
                    )
                }
                PermissionRow(
                    title: "Accessibility",
                    isGranted: model.hasAccessibilityAccess,
                    action: {
                        AccessibilityAccess.request()
                        SystemSettings.open(.accessibility)
                    }
                )
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
        .animation(.smooth(duration: 0.25), value: model.switchingMethod)
    }

    private var switchDelaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Switch after") {
                    Text(model.switchDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        + Text(" s")
                }
                Slider(value: $model.switchDelay, in: Preferences.switchDelayRange, step: 0.1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Quick").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Steady").font(.caption).foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(
                "How long you face another display before the pointer and keyboard move there. "
                    + "Longer means quick glances never switch.")
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: action)
            }
        }
    }
}

// MARK: - Displays

private struct DisplaySettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                DisplayMap(displays: model.displays, focusedID: model.highlightedDisplay)
                    .padding(.vertical, 8)
            }

            if model.switchingMethod.usesCamera {
                Section {
                    ForEach(model.displays) { display in
                        LabeledContent(display.name) {
                            calibrationStatus(for: display)
                        }
                    }
                } footer: {
                    Text(
                        "Calibrate again after moving a display, or if Glazer picks the wrong one. "
                            + "You look at and click a dot at the centre and corners of each display.")
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Calibrate Displays…") { model.calibrate() }
                            .disabled(!model.canCalibrate)
                    }
                }
            } else {
                Section {
                    LabeledContent("Next display") {
                        Text(model.switchShortcut.displayString)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(
                        "Each press of the shortcut moves to the next display, top to bottom, then left to "
                            + "right. Calibration is only needed when Glazer follows where you look.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }

    @ViewBuilder
    private func calibrationStatus(for display: Display) -> some View {
        if let calibration = model.calibration, calibration.pose(for: display.id) != nil {
            if calibration.hasCorners {
                Label("Calibrated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                // Calibrated by Glazer 0.1, at the centre only.
                Label("Centre only", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Calibrate again to add the corners, so Glazer knows where each display ends.")
            }
        } else {
            Label("Not calibrated", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Face lock

private struct FaceLockSettings: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var status: (title: String, detail: String, symbol: String, isActive: Bool) {
        switch model.faceLock {
        case .off:
            (
                "Face lock is off", "Glazer follows the person nearest the camera.",
                "person.crop.circle.badge.questionmark", false
            )
        case .stored, .ready:
            ("Face lock is on", "Glazer follows only you, even with other people in view.", "faceid", true)
        case .unreadable:
            (
                "Face lock is paused", "Glazer couldn't read it from the Keychain, so it isn't following anyone.",
                "key.slash", false
            )
        case .needsReenrolment:
            (
                "Face lock needs setting up again",
                "This version reads faces differently. Until then, Glazer "
                    + "follows the nearest person.", "arrow.triangle.2.circlepath", false
            )
        }
    }

    private func openSetup() {
        openWindow(id: WindowID.faceLock)
        NSApp.activate()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: status.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(status.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(status.title)
                                .font(.headline)
                            ExperimentalBadge()
                        }
                        Text(status.detail)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch model.faceLock {
                    case .off:
                        Button("Set Up…", action: openSetup)
                            .disabled(model.cameraAccess != .granted)
                    case .needsReenrolment:
                        Button("Set Up Again…", action: openSetup)
                            .disabled(model.cameraAccess != .granted)
                    case .unreadable:
                        Button("Try Again") { model.retryFaceLock() }
                    case .stored, .ready:
                        Button("Delete Face…", role: .destructive) {
                            Task { _ = await model.deleteFaceLock() }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("How your face is kept") {
                Fact(symbol: "lock.fill", text: "A face signature (a list of numbers), never a photo.")
                Fact(symbol: "key.fill", text: "Stored only in your login Keychain, encrypted with your password.")
                Fact(symbol: "icloud.slash", text: "Never synced to iCloud and never sent anywhere.")
                Fact(symbol: "touchid", text: "Setting up or deleting it needs Touch ID or your password.")
            }

            Section {
                Text(
                    "Face lock is experimental. It uses a general image comparison built into macOS, "
                        + "because Apple doesn't offer face recognition to apps. It tells you apart from most "
                        + "people, but not reliably from everyone, and it isn't a security feature like Touch ID."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    var body: some View {
        Form {
            Section("What Glazer does") {
                Fact(symbol: "video", text: "Uses the camera only while it's on, and the camera light shows it.")
                Fact(symbol: "cpu", text: "Analyses each frame on this Mac with Apple's Vision framework.")
                Fact(symbol: "trash", text: "Discards every frame immediately after analysis.")
            }
            Section("What Glazer never does") {
                Fact(symbol: "record.circle", text: "Record, save or upload video or photos.")
                Fact(symbol: "network.slash", text: "Connect to the internet. No analytics, no tracking, no updates.")
                Fact(symbol: "eye.slash", text: "Read window titles or what's on your screen.")
            }
            Section {
                Link(
                    "Read the privacy statement",
                    destination: URL(string: "https://github.com/phanipaladugula/glazer/blob/main/docs/PRIVACY.md")
                        ?? URL(fileURLWithPath: "/")
                )
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

private struct Fact: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            if model.gaze.mode == .idle {
                Section {
                    Text(
                        "Glazer isn't using the camera right now. Readings appear while it's following you, "
                            + "calibrating or setting up face lock."
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                let diagnostics = model.gaze.diagnostics
                let output = model.gaze.output
                Section("Live") {
                    Reading("Status", value: statusText(output?.status))
                    Reading("Faces in view", value: "\(diagnostics.faceCount)")
                    Reading("Head yaw", value: degrees(output?.pose?.yaw ?? diagnostics.rawPose?.yaw))
                    Reading("Head pitch", value: degrees(output?.pose?.pitch ?? diagnostics.rawPose?.pitch))
                    Reading("Display in focus", value: displayName(output?.focusedDisplay))
                }
                Section("Camera") {
                    Reading(
                        "Brightness", value: diagnostics.brightness.formatted(.percent.precision(.fractionLength(0))))
                    Reading("Light", value: lightText(output?.lightLevel))
                    Reading(
                        "Frames per second",
                        value: diagnostics.framesPerSecond.formatted(.number.precision(.fractionLength(0))))
                }
                if model.isFaceLockOn, let template = model.faceTemplate {
                    Section("Face lock") {
                        Reading(
                            "Match score",
                            value: diagnostics.matchScore.map { $0.formatted(.number.precision(.fractionLength(3))) }
                                ?? "—")
                        Reading(
                            "Needed to match",
                            value: template.threshold.formatted(.number.precision(.fractionLength(3))))
                    }
                }
            }
            if let calibration = model.calibration {
                Section("Calibration") {
                    ForEach(calibration.displayIDs, id: \.self) { id in
                        if let centre = calibration.pose(for: id) {
                            Reading(
                                displayName(id),
                                value: "\(degrees(centre.yaw)) yaw, \(degrees(centre.pitch)) pitch")
                        }
                        if calibration.hasCorners, let region = calibration.region(for: id) {
                            Reading("  Spans", value: span(of: region))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }

    private func degrees(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(1))))°" } ?? "—"
    }

    /// The range of yaw and pitch a display's corners cover.
    private func span(of region: PoseRegion) -> String {
        let yaws = region.vertices.map(\.yaw), pitches = region.vertices.map(\.pitch)
        return
            "\(degrees(yaws.min()))…\(degrees(yaws.max())) yaw, \(degrees(pitches.min()))…\(degrees(pitches.max())) pitch"
    }

    private func displayName(_ id: Display.ID?) -> String {
        guard let id else { return "—" }
        return model.displays.first { $0.id == id }?.shortName ?? "Display \(id)"
    }

    private func statusText(_ status: GazeEngine.Status?) -> String {
        switch status {
        case .following: "Following"
        case .searching, nil: "Looking for you"
        case .tooDark: "Too dark"
        case .notRecognized: "Face not recognised"
        }
    }

    private func lightText(_ level: LightLevel?) -> String {
        switch level {
        case .good: "Good"
        case .dim: "Dim"
        case .tooDark: "Too dark"
        case nil: "—"
        }
    }
}

private struct Reading: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
