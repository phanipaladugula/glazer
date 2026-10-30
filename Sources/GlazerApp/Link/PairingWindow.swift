import AppKit
import GlazerSystem
import SwiftUI

/// The window that shows a pairing: the code to compare, and Pair or Doesn't Match.
///
/// A window of its own, not a sheet in Settings, because the other Mac can ask to pair at
/// any time, with Settings closed.
@MainActor
final class PairingWindow: NSObject, NSWindowDelegate {
    static let shared = PairingWindow()

    private var window: NSWindow?
    private weak var controller: LinkController?

    func show(controller: LinkController) {
        self.controller = controller
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Pair Mac"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: PairingView(controller: controller) { [weak self] in
                    self?.window?.close()
                })
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        controller?.closePairing()
        window = nil
    }
}

private struct PairingView: View {
    let controller: LinkController
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if let pairing = controller.pairing {
                content(pairing)
            } else {
                Text("No pairing in progress.")
                    .foregroundStyle(.secondary)
                Button("Close", action: close)
            }
        }
        .padding(28)
        .frame(width: 380, height: 300)
        .animation(.smooth(duration: 0.25), value: controller.pairing?.state)
    }

    private func name(_ pairing: PairingModel) -> String {
        pairing.attempt.peer?.name ?? "the other Mac"
    }

    @ViewBuilder
    private func content(_ pairing: PairingModel) -> some View {
        switch pairing.state {
        case .connecting:
            ProgressView()
                .controlSize(.large)
            Text("Connecting to \(name(pairing))…")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                pairing.attempt.decline(); close()
            }
            .keyboardShortcut(.cancelAction)

        case .confirming(let code), .waitingForOther(let code):
            Image(systemName: "laptopcomputer.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Pair with \(name(pairing))?")
                    .font(.title3.weight(.semibold))
                Text("Check that \(name(pairing)) shows the same code.")
                    .foregroundStyle(.secondary)
            }
            CodeView(code: code)
            Spacer()
            if case .waitingForOther = pairing.state {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for \(name(pairing))…")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Button("Doesn't Match") { pairing.attempt.decline() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Pair") { pairing.attempt.accept() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .paired(let peer):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Paired with \(peer.name)")
                .font(.title3.weight(.semibold))
            Text("Look at either Mac to use it with the keyboard and mouse in front of you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done", action: close)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

        case .failed(let failure):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Not paired")
                .font(.title3.weight(.semibold))
            Text(message(failure, name: name(pairing)))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close", action: close)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func message(_ failure: PairingAttempt.Failure, name: String) -> String {
        switch failure {
        case .declined: "Pairing was cancelled on one of the Macs."
        case .mismatch: "The codes didn't match, so nothing was paired. Try again."
        case .connectionLost: "\(name) went away. Check both Macs are on the same network, and try again."
        case .timedOut: "Nobody answered in time. Try again with both Macs in front of you."
        case .couldNotSave: "The pairing couldn't be saved to the Keychain."
        }
    }
}

/// A six-digit code, in two groups of three, as macOS shows codes.
private struct CodeView: View {
    let code: String

    var body: some View {
        Text("\(code.prefix(3)) \(code.suffix(3))")
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .tracking(4)
            .textSelection(.disabled)
            .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
    }
}
