import AppKit
import GlazerSystem
import SwiftUI

/// The panel that opens from the menu bar icon. See `docs/design/README.md`.
struct StatusPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let presentation = ConditionPresentation(model.condition)

        VStack(spacing: 0) {
            StatusHeader(presentation: presentation, isEnabled: $model.isEnabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if let callout = presentation.callout {
                CalloutCard(text: callout.text, button: callout.button) {
                    perform(callout.action)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if case .running = model.condition, !model.hasAccessibilityAccess {
                // Glazer runs, but without Accessibility only the pointer moves.
                CalloutCard(text: "Allow Accessibility so the keyboard follows you too.", button: "Allow…") {
                    AccessibilityAccess.request()
                    SystemSettings.open(.accessibility)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            DisplayMap(
                displays: model.displays,
                focusedID: model.isEnabled ? model.highlightedDisplay : nil
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()

            VStack(spacing: 0) {
                MenuRow(
                    model.isEnabled ? "Turn Off" : "Turn On",
                    shortcut: model.toggleShortcut.displayString,
                    action: model.toggle
                )
                MenuRow("Calibrate Displays…") { perform(.calibrate) }
                    .disabled(!model.canCalibrate)
                MenuRow("Settings…", shortcut: "⌘,") { showSettings() }
                    .keyboardShortcut(",")
            }
            .padding(5)

            Divider()

            VStack(spacing: 0) {
                MenuRow("About Glazer") {
                    NSApp.activate()
                    NSApp.orderFrontStandardAboutPanel()
                }
                MenuRow("Quit Glazer", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(5)
        }
        .frame(width: 300)
        .animation(.easeOut(duration: 0.2), value: model.condition)
        .onAppear {
            model.displayMonitor.start()
            model.refreshPermissions()
        }
        .onDisappear { model.displayMonitor.stop() }
    }

    private func perform(_ action: ConditionPresentation.Action) {
        switch action {
        case .openSetup:
            openWindow(id: WindowID.setup)
            NSApp.activate()
        case .openCameraSettings:
            SystemSettings.open(.camera)
        case .calibrate:
            model.calibrate()
        case .retryFaceLock:
            model.retryFaceLock()
        }
    }

    private func showSettings() {
        openSettings()
        NSApp.activate()
    }
}

private struct StatusHeader: View {
    let presentation: ConditionPresentation
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "eye" : "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(presentation.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(presentation.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Glazer")
                    .font(.headline)
                Text(presentation.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            Toggle("Glazer", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A short explanation of what Glazer needs, with the button that fixes it.
private struct CalloutCard: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(button, action: action)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
