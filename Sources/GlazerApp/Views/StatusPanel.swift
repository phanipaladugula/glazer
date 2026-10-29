import AppKit
import SwiftUI

/// The panel that opens from the menu bar icon. See `docs/design/menu-bar.md`.
struct StatusPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(isEnabled: $model.isEnabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider()

            DisplayMap(
                displays: model.displayMonitor.displays,
                focusedID: model.isEnabled ? model.displayMonitor.pointerDisplayID : nil
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
        .animation(.easeOut(duration: 0.2), value: model.isEnabled)
        .onAppear { model.displayMonitor.start() }
        .onDisappear { model.displayMonitor.stop() }
    }
}

private struct StatusHeader: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "eye" : "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Glazer")
                    .font(.headline)
                Text(isEnabled ? "Following your gaze" : "Off. Camera is not in use")
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
