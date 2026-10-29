import AppKit
import GlazerCore
import SwiftUI

/// During hand calibration, a prompt in the middle of the display the user should hold
/// their hand towards, so they know where to turn.
@MainActor
final class AimPromptOverlay {
    private var panel: NSPanel?
    private var host: NSHostingView<AimPrompt>?
    private var displayID: Display.ID?

    func show(on display: Display, number: Int, of count: Int, recording: Double?) {
        let prompt = AimPrompt(name: display.name, number: number, count: count, recording: recording)
        if let host, displayID == display.id {
            host.rootView = prompt
            return
        }
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display.id }) else { return }

        let host = NSHostingView(rootView: prompt)
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: CGRect(
                x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        self.host = host
        displayID = display.id
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        host = nil
        displayID = nil
    }
}

/// "Hold your open hand towards this display", with how far recording has got.
struct AimPrompt: View {
    let name: String
    let number: Int
    let count: Int
    /// The fraction recorded, or `nil` while waiting for the hand.
    let recording: Double?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 4) {
                Text("Display \(number) of \(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.title2.weight(.semibold))
            }
            Text(
                recording == nil
                    ? "Look here and hold your open hand up towards this display."
                    : "Hold still…"
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(width: 260)
            ProgressView(value: recording ?? 0)
                .frame(width: 220)
                .opacity(recording == nil ? 0.35 : 1)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
        .padding(30)
    }
}
