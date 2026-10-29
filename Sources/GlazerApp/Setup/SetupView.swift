import GlazerCore
import GlazerSystem
import SwiftUI

/// The first-run setup window: how to switch displays, permissions, and for the camera,
/// calibration and, optionally, face lock.
struct SetupView: View {
    @Bindable var model: AppModel

    @State private var step = Step.welcome
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    enum Step: CaseIterable {
        case welcome, method, camera, accessibility, calibration, faceLock, done
    }

    /// The steps for the chosen way of switching. Switching only by key needs no camera,
    /// so it skips the camera, calibration and face lock.
    private var steps: [Step] {
        model.switchingMethod.usesCamera
            ? Step.allCases
            : [.welcome, .method, .accessibility, .done]
    }

    private var stepIndex: Int {
        steps.firstIndex(of: step) ?? 0
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
                StepDots(current: stepIndex, count: steps.count)
                Spacer()
                if step != .welcome, step != .done {
                    Button("Back") { move(by: -1) }
                }
                primaryButton
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
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
                    + "keyboard focus to where you're looking, or wherever a double-press of a key sends it."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "rectangle.on.rectangle", text: "Follows where you look, or a key you double-press")
                    Feature(symbol: "lock.laptopcomputer", text: "Runs entirely on this Mac. No network, ever")
                    Feature(symbol: "video.slash", text: "Never records or saves video")
                }
            }
        case .method:
            SetupPage(
                symbol: "arrow.left.arrow.right", title: "How do you want to switch?",
                message: "You can change this any time in Settings."
            ) {
                VStack(spacing: 8) {
                    ForEach(SwitchingMethod.allCases, id: \.self) { method in
                        MethodOption(method: method, isSelected: model.switchingMethod == method) {
                            model.switchingMethod = method
                        }
                    }
                    if model.switchingMethod.usesKey {
                        Picker("Double-press", selection: $model.switchKey) {
                            ForEach(SwitchKey.allCases, id: \.self) { key in
                                Text(key.name).tag(key)
                            }
                        }
                        .fixedSize()
                        .padding(.top, 6)
                        .help(model.switchKey.caveat ?? "")
                    }
                }
                .frame(maxWidth: 420)
                .animation(.smooth(duration: 0.25), value: model.switchingMethod)
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
                message: model.switchingMethod.usesCamera
                    ? "Glazer needs this to move your typing to the display you look at, and to wait "
                        + "while you type. Until it's allowed, Glazer stays paused."
                    : "Glazer needs this to notice your double-press in any app, and to move your typing "
                        + "to the next display. It only sees which modifier keys go up and down."
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
                message: "Glazer shows a dot at the centre and corners of each display. Look at each dot "
                    + "and click it, so Glazer learns where each display starts and ends. It takes about "
                    + "half a minute."
            ) {
                if model.displays.count < 2 {
                    Callout(
                        symbol: "display.2",
                        text: "Connect a second display to calibrate. You can do it later from the menu bar.")
                } else if model.calibration?.covers(model.displays) == true {
                    VStack(spacing: 10) {
                        PermissionStatus(isGranted: true, grantedText: "Your displays are calibrated", action: nil)
                        Button("Calibrate Again") { model.calibrate { _ in NSApp.activate() } }
                            .buttonStyle(.link)
                    }
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
                message: doneMessage
            ) {
                EmptyView()
            }
        }
    }

    private var doneMessage: String {
        let toggle = "Press \(model.toggleShortcut.displayString) anywhere to turn it on or off."
        guard model.switchingMethod.usesKey else { return "Glazer lives in the menu bar. \(toggle)" }
        return "Double-press \(model.switchKey.shortName) to jump to the next display. Glazer lives in the "
            + "menu bar. \(toggle)"
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
        let index = stepIndex + offset
        guard steps.indices.contains(index) else { return }
        step = steps[index]
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

/// One way of switching, as a row that's selected by clicking it.
private struct MethodOption: View {
    let method: SwitchingMethod
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: method.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.title)
                        .font(.body.weight(.medium))
                    Text(method.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quinary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
