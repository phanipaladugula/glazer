import GlazerCore
import SwiftUI

/// The hand gesture calibration window.
struct HandCalibrationView: View {
    let model: AppModel
    @State private var flow: HandCalibrationFlow
    @Environment(\.dismissWindow) private var dismissWindow

    init(model: AppModel) {
        self.model = model
        _flow = State(initialValue: HandCalibrationFlow(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
                .padding(.top, 32)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 40, alignment: .top)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)

            if flow.step == .trying {
                TrialResults(flow: flow)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Spacer(minLength: 16)

            Divider()
            HStack {
                if flow.step == .intro {
                    Label("Only hand measurements are kept", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                buttons
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
        .animation(.smooth(duration: 0.3), value: flow.step)
        .animation(.smooth(duration: 0.2), value: flow.shapes.progress)
        .animation(.smooth(duration: 0.2), value: flow.grabs + flow.drops)
        .onDisappear { flow.cancel() }
    }

    // MARK: Viewfinder

    private var isCameraOn: Bool {
        flow.step == .shapes || flow.step == .aiming || flow.step == .trying
    }

    private var viewfinder: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isCameraOn {
                    CameraPreview(session: model.gaze.camera.session)
                } else {
                    ZStack {
                        Rectangle().fill(.quinary)
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(placeholderStyle)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(width: 380, height: 240)

            switch flow.step {
            case .shapes:
                StepPills(
                    titles: flow.shapes.configuration.shapes.map { $0 == .open ? "Open" : "Fist" },
                    step: flow.shapes.step, fraction: fraction(of: flow.shapes.progress)
                )
                .padding(10)
            case .aiming:
                if let aiming = flow.aiming {
                    StepPills(
                        titles: aiming.displays.map { id in
                            flow.displays.first { $0.id == id }?.shortName ?? "Display"
                        },
                        step: aiming.step, fraction: fraction(of: aiming.progress)
                    )
                    .padding(10)
                }
            case .trying:
                OpennessMeter(openness: flow.openness)
                    .padding(10)
            case .intro, .failed:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private func fraction(of progress: HandCalibrationRecorder.Progress) -> Double? {
        if case .recording(_, let fraction) = progress { fraction } else { nil }
    }

    private func fraction(of progress: HandAimRecorder.Progress) -> Double? {
        if case .recording(_, let fraction) = progress { fraction } else { nil }
    }

    private var placeholderSymbol: String {
        if case .failed = flow.step { return "exclamationmark.triangle.fill" }
        return "hand.raised.fingers.spread.fill"
    }

    private var placeholderStyle: AnyShapeStyle {
        if case .failed = flow.step { return AnyShapeStyle(.yellow) }
        return AnyShapeStyle(.tint)
    }

    // MARK: Text

    private var title: String {
        switch flow.step {
        case .intro: "Calibrate Hand Gestures"
        case .shapes:
            switch flow.shapes.progress {
            case .waiting(.open), .recording(.open, _): "Open hand"
            case .waiting(.fist), .recording(.fist, _): "Fist"
            case .finished, .failed: ""
            }
        case .aiming: "Point at each display"
        case .trying: "Try it"
        case .failed: "Calibration didn't work"
        }
    }

    private var message: String {
        switch flow.step {
        case .intro:
            return "Glazer learns how your open hand and your fist look to this camera, then where you hold "
                + "your hand for each display. Sit as you usually do. It takes about half a minute."
        case .shapes:
            guard flow.seesFace else {
                return "Face the camera: Glazer matches your hand to your face, so other people's hands never count."
            }
            switch flow.shapes.progress {
            case .waiting(.open):
                return flow.seesHand
                    ? "Hold still, with your fingers spread."
                    : "Raise your hand beside your face, open, with your palm towards the camera."
            case .waiting(.fist):
                return flow.seesHand ? "Hold still." : "Now close it into a fist, in the same place."
            case .recording(.open, _): return "Keep it open…"
            case .recording(.fist, _): return "Keep the fist…"
            case .finished, .failed: return ""
            }
        case .aiming:
            return "Turn to the display showing the hand, and hold your open hand up towards it until it fills. "
                + "Then the next one."
        case .trying:
            if flow.aim != nil {
                return "Grab facing one display, turn, and drop facing another. "
                    + "Glazer shows which display your hand is held towards. No screenshot is taken."
            }
            if flow.aimProblem != nil {
                return "Your hand was in about the same place for each display, so Glazer will choose the display "
                    + "you look at. Open your hand, close it to grab, open it to drop."
            }
            return "Open your hand, then close it to grab. Open it again to drop. No screenshot is taken."
        case .failed(.tooSimilar):
            return "Your open hand and your fist looked too alike to the camera. "
                + "Try brighter light, or hold your hand a little closer."
        case .failed(.tooFewReadings):
            return "Glazer didn't see your hand for long enough. Keep it in view while each shape is recorded."
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        switch flow.step {
        case .intro:
            Button("Cancel") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
            Button("Start") { flow.start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .shapes, .aiming:
            Button("Cancel") { flow.cancel() }
                .keyboardShortcut(.cancelAction)
        case .trying:
            Button("Redo") { flow.start() }
            Button("Save") {
                flow.save()
                dismissWindow()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
            Button("Try Again") { flow.start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// One pill per step, filled as it's recorded.
private struct StepPills: View {
    let titles: [String]
    let step: Int
    /// How far the current step has been recorded, or `nil` while it waits.
    let fraction: Double?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .lineLimit(1)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        GeometryReader { geometry in
                            Capsule().fill(.tint.opacity(0.35))
                                .frame(width: geometry.size.width * fill(index))
                        }
                    }
                    .background(.thinMaterial, in: Capsule())
                    .clipShape(Capsule())
                    .opacity(index <= step ? 1 : 0.6)
            }
        }
    }

    private func fill(_ index: Int) -> CGFloat {
        if index < step { return 1 }
        return index == step ? fraction ?? 0 : 0
    }
}

/// How open the hand is, between the user's fist and their open hand.
private struct OpennessMeter: View {
    let openness: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text("Fist")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.tint)
                        .frame(width: max(8, geometry.size.width * (openness ?? 0)))
                        .opacity(openness == nil ? 0 : 1)
                }
            }
            .frame(height: 6)
            Text("Open")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .animation(.easeOut(duration: 0.1), value: openness)
    }
}

/// What the trial has recognised so far, and where the hand is held.
private struct TrialResults: View {
    let flow: HandCalibrationFlow

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                count("Grabs", flow.grabs, active: flow.isHolding)
                count("Drops", flow.drops, active: false)
            }
            if flow.aim != nil {
                Label {
                    Text(aimedName)
                        .contentTransition(.opacity)
                } icon: {
                    Image(systemName: "hand.point.up.left")
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .animation(.smooth(duration: 0.2), value: flow.aimedAt)
    }

    private var aimedName: String {
        guard let id = flow.aimedAt, let display = flow.displays.first(where: { $0.id == id }) else {
            return "Hold your hand towards a display"
        }
        return "Towards \(display.name)"
    }

    private func count(_ title: String, _ value: Int, active: Bool) -> some View {
        Label {
            Text("\(title) \(value)")
                .monospacedDigit()
        } icon: {
            Image(systemName: value > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(value > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .symbolEffect(.pulse, isActive: active)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
