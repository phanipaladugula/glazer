import AppKit
import GlazerCore
import GlazerSystem
import SwiftUI

/// Shows the switch shortcut, and records a new one: click it, then press the keys.
///
/// The new shortcut is checked as it's pressed. One with too few modifiers, or that turns
/// Glazer on and off, is refused with the reason, and the old one stays. Escape, or
/// clicking it again, cancels.
struct ShortcutRecorder: View {
    let model: AppModel

    @State private var isRecording = false
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut…" : model.switchShortcut.displayString)
                    .frame(minWidth: 112)
            }
            .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to change the shortcut")
            .accessibilityLabel("Switch shortcut")
            .accessibilityValue(model.switchShortcut.displayString)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let error = model.switchShortcutError {
                Text(Self.text(for: error))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.smooth(duration: 0.2), value: message)
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        message = nil
        isRecording = true
        // Release the current shortcut, so pressing it reaches the recorder.
        model.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        model.isRecordingShortcut = false
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            stopRecording()
            return
        }
        guard let key = KeyCodes.key(for: event.keyCode) else {
            message = "Use a letter, a number, an arrow or Space."
            return
        }
        let shortcut = GlazerCore.KeyboardShortcut(key: key, modifiers: Self.modifiers(of: event))
        switch shortcut.problemAsSwitchShortcut {
        case .needsMoreModifiers:
            message = "Use two of ⌃, ⌥ and ⌘, so apps keep their shortcuts."
        case .sameAsToggle:
            message = "\(shortcut.displayString) turns Glazer on and off."
        case nil:
            message = nil
            model.switchShortcut = shortcut
            stopRecording()
        }
    }

    private static func modifiers(of event: NSEvent) -> GlazerCore.KeyboardShortcut.Modifiers {
        let flags = event.modifierFlags
        var modifiers: GlazerCore.KeyboardShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func text(for error: HotKey.Error) -> String {
        switch error {
        case .reservedBySystem:
            "macOS already uses this shortcut."
        case .takenByAnotherApp:
            "Another app already uses this shortcut."
        case .unsupportedKey, .registrationFailed:
            "This shortcut couldn't be set up."
        }
    }
}
