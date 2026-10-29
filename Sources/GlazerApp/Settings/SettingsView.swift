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
            }

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

            Section("Permissions") {
                PermissionRow(
                    title: "Camera",
                    isGranted: model.cameraAccess == .granted,
                    action: { SystemSettings.open(.camera) }
                )
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

            Section {
                ForEach(model.displays) { display in
                    LabeledContent(display.name) {
                        if model.calibration?.pose(for: display.id) != nil {
                            Label("Calibrated", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not calibrated", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                Text("Calibrate again after moving a display, or if Glazer picks the wrong one.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Calibrate Displays…") { model.calibrate() }
                        .disabled(!model.canCalibrate)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

// MARK: - Face lock

private struct FaceLockSettings: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: model.isFaceLockOn ? "faceid" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundStyle(model.isFaceLockOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isFaceLockOn ? "Face lock is on" : "Face lock is off")
                            .font(.headline)
                        Text(
                            model.isFaceLockOn
                                ? "Glazer follows only you, even with other people in view."
                                : "Glazer follows the person nearest the camera."
                        )
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isFaceLockOn {
                        Button("Delete Face…", role: .destructive) {
                            Task { _ = await model.deleteFaceLock() }
                        }
                    } else {
                        Button("Set Up…") {
                            openWindow(id: WindowID.faceLock)
                            NSApp.activate()
                        }
                        .disabled(model.cameraAccess != .granted)
                    }
                }
                .padding(.vertical, 4)
            }

            if model.faceLockNeedsReenrolment {
                Section {
                    Label(
                        "This version of Glazer reads faces differently. Set up face lock again to keep using it.",
                        systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section("How your face is kept") {
                Fact(symbol: "lock.fill", text: "A face signature (a list of numbers), never a photo.")
                Fact(symbol: "key.fill", text: "Stored only in your login Keychain, encrypted with your password.")
                Fact(symbol: "icloud.slash", text: "Never synced to iCloud and never sent anywhere.")
                Fact(symbol: "touchid", text: "Setting up or deleting it needs Touch ID or your password.")
            }

            Section {
                Text(
                    "Face lock tells you apart from other people in view of the camera. It isn't a security "
                        + "feature like Touch ID: someone who looks very like you may be recognised as you."
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
                    Text("Glazer isn't using the camera right now. Turn it on to see live readings.")
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
                    ForEach(calibration.points, id: \.displayID) { point in
                        Reading(
                            displayName(point.displayID),
                            value: "\(degrees(point.pose.yaw)) yaw, \(degrees(point.pose.pitch)) pitch")
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
