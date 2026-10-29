import GlazerCore
import SwiftUI

/// The full-screen overlay shown on one display during calibration.
///
/// The display being calibrated shows a target and a progress ring. The others dim and
/// point towards it. When calibration ends, the display with the menu bar shows the
/// result.
struct CalibrationOverlay: View {
    let session: CalibrationSession
    let display: Display
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDone: (Calibration) -> Void

    var body: some View {
        ZStack {
            backdrop
            content
                .frame(maxWidth: 520)
                .padding(40)
        }
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.35), value: session.phase)
    }

    private var isCurrent: Bool {
        session.currentDisplay?.id == display.id
    }

    private var backdrop: some View {
        Rectangle()
            .fill(.black.opacity(isCurrent ? 0.55 : 0.78))
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .recording(let index):
            if isCurrent {
                RecordingPrompt(
                    step: index + 1,
                    stepCount: session.displays.count,
                    progress: session.progress,
                    hint: session.hint,
                    onCancel: onCancel
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let current = session.currentDisplay {
                LookElsewherePrompt(target: current, from: display)
                    .transition(.opacity)
            }
        case .finished(let calibration):
            if display.hasMenuBar {
                ResultCard(
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    title: "Calibration complete",
                    message: "Glazer can now tell your displays apart. Look at another display "
                        + "and the pointer and keyboard follow.",
                    primary: ("Done", { onDone(calibration) }),
                    secondary: nil
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        case .failed(.displaysTooClose):
            if display.hasMenuBar {
                ResultCard(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .yellow,
                    title: "Your displays look the same from here",
                    message: "Glazer couldn't tell them apart, because your head pointed the same way "
                        + "for each. Turn your head towards each display, not just your eyes.",
                    primary: ("Try Again", onRetry),
                    secondary: ("Cancel", onCancel)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }
}

private struct RecordingPrompt: View {
    let step: Int
    let stepCount: Int
    let progress: Double
    let hint: CalibrationSession.Hint
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("Display \(step) of \(stepCount)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text("Look at this display")
                    .font(.system(size: 34, weight: .semibold))
                Text("Turn your head to face the dot, then hold still for a moment.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Target(progress: progress)
                .padding(.vertical, 12)

            HintLabel(hint: hint)
                .frame(height: 22)

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("Esc")
        }
    }
}

/// A dot inside a ring that fills as calibration records.
private struct Target: View {
    let progress: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: progress)
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 44, height: 44)
                .scaleEffect(pulse ? 1.25 : 0.85)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .shadow(color: .white.opacity(0.6), radius: 8)
        }
        .frame(width: 132, height: 132)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Calibration target")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct HintLabel: View {
    let hint: CalibrationSession.Hint

    var body: some View {
        if let text {
            Label(text, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(.yellow)
                .transition(.opacity)
        }
    }

    private var text: String? {
        switch hint {
        case .none: nil
        case .cantSeeYou: "Can't see you. Make sure your face is in view of the camera."
        case .tooDark: "Too dark to see you. Turn on a light in front of you."
        case .notRecognized: "Face lock doesn't recognise you. Calibration needs the enrolled user."
        case .holdStill: "Hold still while the ring fills."
        }
    }

    private var symbol: String {
        switch hint {
        case .tooDark: "moon.fill"
        case .holdStill: "hand.raised.fill"
        default: "eye.trianglebadge.exclamationmark"
        }
    }
}

/// Shown on displays that aren't being calibrated: points the user to the one that is.
private struct LookElsewherePrompt: View {
    let target: Display
    let from: Display

    var body: some View {
        Label("Look at \(target.shortName)", systemImage: arrow)
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private var arrow: String {
        let dx = target.frame.midX - from.frame.midX
        let dy = target.frame.midY - from.frame.midY
        if abs(dx) >= abs(dy) {
            return dx < 0 ? "arrow.left" : "arrow.right"
        }
        return dy < 0 ? "arrow.down" : "arrow.up"
    }
}

private struct ResultCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
                Button(primary.0, action: primary.1)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }
}
