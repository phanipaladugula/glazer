import GlazerCore
import SwiftUI

/// The full-screen overlay shown on one display during calibration.
///
/// The display being calibrated shows a dot, at its centre and then at each corner, that
/// the user looks at and clicks; a ring around it fills while it records. The other
/// displays dim and point towards it. When calibration ends, the display with the menu bar
/// shows the result.
struct CalibrationOverlay: View {
    let session: CalibrationSession
    let display: Display
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDone: (Calibration) -> Void

    var body: some View {
        ZStack {
            backdrop
            if isCurrent, let target = session.currentTarget {
                DotField(
                    spot: target.spot, progress: session.progress, isArmed: session.isArmed,
                    onClick: session.confirm
                )
                .id(target)
                .transition(.opacity)
            }
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
        case .recording:
            if isCurrent, let target = session.currentTarget, let dot = session.dotStep {
                RecordingPrompt(
                    displayStep: session.displayStep ?? 1,
                    displayCount: session.displays.count,
                    dot: dot,
                    spot: target.spot,
                    isArmed: session.isArmed,
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
                        + "for each. Turn your head towards each dot, not just your eyes.",
                    primary: ("Try Again", onRetry),
                    secondary: ("Cancel", onCancel)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        case .failed(.cameraStopped):
            if display.hasMenuBar {
                ResultCard(
                    symbol: "video.slash.fill",
                    tint: .yellow,
                    title: "The camera stopped",
                    message: "It may have been disconnected, or another app may be using it. "
                        + "Check the camera, then try again.",
                    primary: ("Try Again", onRetry),
                    secondary: ("Cancel", onCancel)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }
}

/// The words in the middle of the display being calibrated. They leave room in the middle
/// for the centre dot; for a corner dot, an arrow there points to it.
private struct RecordingPrompt: View {
    let displayStep: Int
    let displayCount: Int
    let dot: (number: Int, count: Int)
    let spot: Calibration.Spot
    let isArmed: Bool
    let hint: CalibrationSession.Hint
    let onCancel: () -> Void

    /// The space between the slot in the middle and the words above and below it.
    private let gap = 28.0

    var body: some View {
        // The slot sits at the exact middle of the display, where the centre dot is drawn;
        // the words hang above and below it, so they never cover the dot.
        ZStack {
            if let arrow = spot.arrowSymbol {
                Image(systemName: arrow)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .transition(.opacity)
            }
        }
        .frame(width: DotField.diameter, height: DotField.diameter)
        .overlay(alignment: .top) {
            instructions
                .frame(width: 520)
                .alignmentGuide(.top) { $0[.bottom] + gap }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 28) {
                HintLabel(hint: hint)
                    .frame(height: 22)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Esc")
            }
            .frame(width: 520)
            .alignmentGuide(.bottom) { $0[.top] - gap }
        }
    }

    private var instructions: some View {
        VStack(spacing: 10) {
            Text("Display \(displayStep) of \(displayCount) · Dot \(dot.number) of \(dot.count)")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
                .contentTransition(.numericText())
            Text(isArmed ? "Keep looking at the dot" : "Look at the dot and click it")
                .font(.system(size: 34, weight: .semibold))
                .contentTransition(.opacity)
            Text("Turn your head to face it, not just your eyes. Press Space if you'd rather not click.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension Calibration.Spot {
    /// An arrow from the middle of the display towards the spot.
    fileprivate var arrowSymbol: String? {
        switch self {
        case .centre: nil
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomRight: "arrow.down.right"
        case .bottomLeft: "arrow.down.left"
        }
    }
}

/// Places the dot at its spot on the display, inset from the edges so it's clear of the
/// menu bar, the notch and the Dock.
private struct DotField: View {
    static let diameter = 96.0
    private static let inset = 84.0

    let spot: Calibration.Spot
    let progress: Double
    let isArmed: Bool
    let onClick: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let position = spot.position
            let x = Self.inset + (geometry.size.width - 2 * Self.inset) * position.x
            let y = Self.inset + (geometry.size.height - 2 * Self.inset) * position.y
            Target(progress: progress, isArmed: isArmed, onClick: onClick)
                .position(x: x, y: y)
        }
        .ignoresSafeArea()
    }
}

/// A dot to click, inside a ring that fills while it records.
private struct Target: View {
    let progress: Double
    let isArmed: Bool
    let onClick: () -> Void
    @State private var pulse = false
    @State private var isHovered = false

    var body: some View {
        Button(action: onClick) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(isHovered || isArmed ? 0.3 : 0.14), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: progress)
                if !isArmed {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulse ? 1.3 : 0.85)
                        .opacity(pulse ? 0 : 1)
                }
                Circle()
                    .fill(isArmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                    .frame(width: 14, height: 14)
                    .shadow(color: .white.opacity(0.6), radius: 8)
            }
            .frame(width: DotField.diameter, height: DotField.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.2), value: isArmed)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel("Calibration dot")
        .accessibilityHint("Look at the dot, then click it.")
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
        case .turnToDisplay: "Turn your head to face this display."
        }
    }

    private var symbol: String {
        switch hint {
        case .tooDark: "moon.fill"
        case .holdStill: "hand.raised.fill"
        case .turnToDisplay: "arrow.left.and.right"
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
