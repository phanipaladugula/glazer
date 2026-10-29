import AVFoundation
import GlazerCore
import SwiftUI

/// The face lock setup window.
struct FaceLockSetupView: View {
    let model: AppModel
    @State private var flow: FaceEnrolmentFlow
    @Environment(\.dismissWindow) private var dismissWindow

    init(model: AppModel) {
        self.model = model
        _flow = State(initialValue: FaceEnrolmentFlow(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScanCircle(session: model.gaze.camera.session, step: flow.step, progress: flow.enrolment.progress)
                .padding(.top, 36)

            VStack(spacing: 8) {
                if flow.step == .intro {
                    ExperimentalBadge()
                }
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 40, alignment: .top)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)

            Spacer(minLength: 20)

            Divider()
            HStack {
                if flow.step == .intro {
                    Label("Stays in your Keychain on this Mac", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                buttons
            }
            .padding(16)
        }
        .frame(width: 440, height: 540)
        .animation(.smooth(duration: 0.3), value: flow.step)
        .animation(.smooth(duration: 0.2), value: flow.enrolment.feedback)
        .onDisappear { flow.cancel() }
    }

    @ViewBuilder
    private var buttons: some View {
        switch flow.step {
        case .intro:
            Button("Cancel") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
            Button("Continue") { Task { await flow.start() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .scanning:
            Button("Cancel") { flow.cancel() }
                .keyboardShortcut(.cancelAction)
        case .saved:
            Button("Done") { dismissWindow() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
            Button("Try Again") { Task { await flow.start() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var title: String {
        switch flow.step {
        case .intro: "Set Up Face Lock"
        case .scanning: "Turn your head slowly"
        case .saved: "Face lock is on"
        case .failed: "Face lock wasn't set up"
        }
    }

    private var message: String {
        switch flow.step {
        case .intro:
            "Glazer will follow only you, even with other people in view. "
                + "You'll confirm with Touch ID, then turn your head slowly from side to side."
        case .scanning:
            switch flow.enrolment.feedback {
            case .lookAtCamera: "Look at the camera, with your face inside the circle."
            case .moveCloser: "Move a little closer to the camera."
            case .onlyOnePerson: "Make sure you're the only person in view."
            case .turnSlowly: "Keep turning left and right until the ring is complete."
            case .restarted: "That looked like someone else, so the scan started over."
            case .done: "Saving…"
            }
        case .saved:
            "Glazer now follows only you. You can delete your face at any time in Settings."
        case .failed(let reason):
            reason
        }
    }
}

/// The camera preview in a circle, ringed by ticks that fill as the scan progresses.
private struct ScanCircle: View {
    let session: AVCaptureSession
    let step: FaceEnrolmentFlow.Step
    let progress: Double

    private let diameter: CGFloat = 220
    private let tickCount = 72

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                Capsule()
                    .fill(isFilled(index) ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: 12)
                    .offset(y: -(diameter / 2 + 18))
                    .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360))
                    .animation(.easeOut(duration: 0.2), value: isFilled(index))
            }

            Group {
                if step == .scanning {
                    CameraPreview(session: session)
                        .transition(.opacity)
                } else {
                    placeholder
                        .transition(.opacity)
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        }
        .frame(width: diameter + 60, height: diameter + 60)
    }

    private func isFilled(_ index: Int) -> Bool {
        switch step {
        case .saved: true
        case .scanning: Double(index) < progress * Double(tickCount)
        case .intro, .failed: false
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            Circle().fill(.quinary)
            Image(systemName: symbol)
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(symbolStyle)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var symbol: String {
        switch step {
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .intro, .scanning: "faceid"
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch step {
        case .saved: AnyShapeStyle(.green)
        case .failed: AnyShapeStyle(.yellow)
        case .intro, .scanning: AnyShapeStyle(.tint)
        }
    }
}
