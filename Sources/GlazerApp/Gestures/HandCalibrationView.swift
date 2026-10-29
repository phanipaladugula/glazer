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
                TrialChecklist(trial: flow.trial)
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
        .frame(width: 460, height: 540)
        .animation(.smooth(duration: 0.3), value: flow.step)
        .animation(.smooth(duration: 0.2), value: flow.recorder.progress)
        .animation(.smooth(duration: 0.2), value: flow.trial)
        .onDisappear { flow.cancel() }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack(alignment: .bottom) {
            Group {
                if flow.step == .recording || flow.step == .trying {
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
            case .recording:
                ShapeSteps(recorder: flow.recorder)
                    .padding(10)
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
        case .recording:
            switch flow.recorder.progress {
            case .waiting(.open), .recording(.open, _): "Open hand"
            case .waiting(.fist), .recording(.fist, _): "Fist"
            case .finished, .failed: ""
            }
        case .trying: "Try it"
        case .failed: "Calibration didn't work"
        }
    }

    private var message: String {
        switch flow.step {
        case .intro:
            "Glazer learns how your open hand and your fist look to this camera, so it can tell them "
                + "apart in your light, at your distance. Sit as you usually do. It takes about 15 seconds."
        case .recording:
            switch flow.recorder.progress {
            case .waiting(.open):
                flow.seesHand
                    ? "Hold still, with your fingers spread."
                    : "Raise your hand beside your face, open, with your palm towards the camera."
            case .waiting(.fist):
                flow.seesHand ? "Hold still." : "Now close it into a fist, in the same place."
            case .recording(.open, _): "Keep it open…"
            case .recording(.fist, _): "Keep the fist…"
            case .finished, .failed: ""
            }
        case .trying:
            "Open your hand, then close it to grab. Open it again to drop. "
                + "Glazer won't take a screenshot while you try."
        case .failed(.tooSimilar):
            "Your open hand and your fist looked too alike to the camera. "
                + "Try brighter light, or hold your hand a little closer."
        case .failed(.tooFewReadings):
            "Glazer didn't see your hand for long enough. Keep it in view while each shape is recorded."
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
        case .recording:
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

/// The four shapes, open and fist twice, with the one being recorded filling up.
private struct ShapeSteps: View {
    let recorder: HandCalibrationRecorder

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(recorder.configuration.shapes.enumerated()), id: \.offset) { index, shape in
                Text(shape == .open ? "Open" : "Fist")
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
                    .opacity(index <= recorder.step ? 1 : 0.6)
            }
        }
    }

    private func fill(_ index: Int) -> CGFloat {
        if index < recorder.step { return 1 }
        guard index == recorder.step, case .recording(_, let fraction) = recorder.progress else { return 0 }
        return fraction
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

/// The two steps of trying a calibration, ticked as they happen.
private struct TrialChecklist: View {
    let trial: HandCalibrationFlow.Trial

    var body: some View {
        HStack(spacing: 20) {
            item("Grab", done: trial != .waitingForGrab)
            item("Drop", done: trial == .dropped)
        }
        .font(.callout)
    }

    private func item(_ title: String, done: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
