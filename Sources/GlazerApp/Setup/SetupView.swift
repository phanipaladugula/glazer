import GlazerSystem
import SwiftUI

/// The first-run setup window: permissions, calibration and, optionally, face lock.
struct SetupView: View {
    let model: AppModel

    @State private var step = Step.welcome
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    enum Step: Int, CaseIterable {
        case welcome, camera, accessibility, calibration, faceLock, done
    }

    var body: some View {
        VStack(spacing: 0) {
            page
                .id(step)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity.combined(with: .offset(x: -24))
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 44)

            Divider()
            HStack {
                StepDots(current: step.rawValue, count: Step.allCases.count)
                Spacer()
                if step != .welcome, step != .done {
                    Button("Back") { move(by: -1) }
                }
                primaryButton
            }
            .padding(16)
        }
        .frame(width: 560, height: 460)
        .animation(.smooth(duration: 0.3), value: step)
        .task {
            // Permissions have no change notifications, so check while setup is open.
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            SetupPage(
                symbol: nil, title: "Welcome to Glazer",
                message: "Look at another display and start typing. Glazer moves the pointer and "
                    + "keyboard focus to where you're looking."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "rectangle.on.rectangle", text: "Follows which display your head is facing")
                    Feature(symbol: "lock.laptopcomputer", text: "Runs entirely on this Mac. No network, ever")
                    Feature(symbol: "video.slash", text: "Never records or saves video")
                }
            }
        case .camera:
            SetupPage(
                symbol: "video", title: "Camera",
                message: "Glazer watches which way your head is turned. Each frame is analysed on this Mac "
                    + "and immediately discarded."
            ) {
                PermissionStatus(
                    isGranted: model.cameraAccess == .granted,
                    grantedText: "Camera access is on",
                    action: cameraAction
                )
            }
        case .accessibility:
            SetupPage(
                symbol: "accessibility", title: "Accessibility",
                message: "Glazer needs this to bring the window you were using on the other display to the "
                    + "front, and to wait while you type. Without it, only the pointer moves."
            ) {
                PermissionStatus(
                    isGranted: model.hasAccessibilityAccess,
                    grantedText: "Accessibility access is on",
                    action: (
                        "Open Accessibility Settings",
                        {
                            AccessibilityAccess.request()
                            SystemSettings.open(.accessibility)
                        }
                    )
                )
            }
        case .calibration:
            SetupPage(
                symbol: "scope", title: "Calibrate your displays",
                message: "Glazer will ask you to look at each display in turn, so it learns which way "
                    + "your head points for each one. It takes about ten seconds."
            ) {
                if model.displays.count < 2 {
                    Callout(
                        symbol: "display.2",
                        text: "Connect a second display to calibrate. You can do it later from the menu bar.")
                } else if model.calibration?.covers(model.displays) == true {
                    PermissionStatus(isGranted: true, grantedText: "Your displays are calibrated", action: nil)
                }
            }
        case .faceLock:
            SetupPage(
                symbol: "faceid", title: "Face lock",
                message: "Optional and experimental. Glazer learns your face, so it follows only you even "
                    + "when other people are in view. Your face signature stays in your Keychain on this Mac."
            ) {
                if model.isFaceLockOn {
                    PermissionStatus(isGranted: true, grantedText: "Face lock is on", action: nil)
                } else {
                    Button("Set Up Face Lock…") { open(WindowID.faceLock) }
                        .controlSize(.large)
                }
            }
        case .done:
            SetupPage(
                symbol: "checkmark.circle", title: "You're all set",
                message: "Glazer lives in the menu bar. Press \(model.toggleShortcut.displayString) anywhere "
                    + "to turn it on or off."
            ) {
                EmptyView()
            }
        }
    }

    private var cameraAction: (String, () -> Void)? {
        switch model.cameraAccess {
        case .notDetermined: ("Allow Camera Access", { Task { await model.requestCameraAccess() } })
        case .denied, .restricted: ("Open Camera Settings", { SystemSettings.open(.camera) })
        case .granted: nil
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .camera where model.cameraAccess != .granted:
            Button("Continue") { move(by: 1) }
                .disabled(true)
        case .accessibility where !model.hasAccessibilityAccess:
            Button("Skip") { move(by: 1) }
        case .calibration where model.displays.count >= 2 && model.calibration?.covers(model.displays) != true:
            Button("Start Calibration") {
                model.calibrate { finished in
                    NSApp.activate()
                    if finished { move(by: 1) }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        case .faceLock where !model.isFaceLockOn:
            Button("Not Now") { move(by: 1) }
        case .done:
            Button("Start Using Glazer") {
                model.completeSetup()
                dismissWindow()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        default:
            Button("Continue") { move(by: 1) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func move(by offset: Int) {
        step = Step(rawValue: step.rawValue + offset) ?? step
    }

    private func open(_ window: String) {
        openWindow(id: window)
        NSApp.activate()
    }
}

// MARK: - Components

private struct SetupPage<Accessory: View>: View {
    /// The page's symbol, shown in an accent badge. `nil` shows the app icon instead.
    let symbol: String?
    let title: String
    let message: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            badge
                .frame(height: 76)

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 16)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            accessory
                .padding(.top, 26)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .accentColor.opacity(0.25), radius: 10, y: 4)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
        }
    }
}

/// Either a confirmation that a permission is on, or the button that turns it on.
private struct PermissionStatus: View {
    let isGranted: Bool
    let grantedText: String
    let action: (String, () -> Void)?

    var body: some View {
        if isGranted {
            Label(grantedText, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body.weight(.medium))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if let action {
            Button(action.0, action: action.1)
                .controlSize(.large)
        }
    }
}

private struct Callout: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.25), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
