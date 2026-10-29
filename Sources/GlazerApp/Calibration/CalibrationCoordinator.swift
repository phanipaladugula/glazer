import AppKit
import GlazerCore
import SwiftUI

/// Shows the calibration overlays on every display and runs a ``CalibrationSession``.
@MainActor
final class CalibrationCoordinator {
    private let gaze: GazeController
    private var windows: [OverlayWindow] = []
    private var session: CalibrationSession?
    private var completion: ((Calibration?) -> Void)?

    init(gaze: GazeController) {
        self.gaze = gaze
    }

    var isRunning: Bool {
        session != nil
    }

    /// Starts calibrating `displays`. `completion` gets the calibration, or `nil` if the
    /// user cancelled.
    func start(displays: [Display], verifier: IdentityVerifier?, completion: @escaping (Calibration?) -> Void) {
        guard session == nil else { return }

        let session = CalibrationSession(displays: displays)
        self.session = session
        self.completion = completion

        for screen in NSScreen.screens {
            guard let display = Display(screen: screen) else { continue }
            let overlay = CalibrationOverlay(
                session: session,
                display: display,
                onCancel: { [weak self] in self?.finish(with: nil) },
                onRetry: { session.restart() },
                onDone: { [weak self] calibration in self?.finish(with: calibration) }
            )
            let window = Self.makeWindow(for: screen, content: overlay)
            window.onCancel = { [weak self] in self?.finish(with: nil) }
            windows.append(window)
        }
        NSApp.activate()
        windows.first { $0.screen == NSScreen.main }?.makeKeyAndOrderFront(nil)

        gaze.calibrate(verifier: verifier) { frame, output in
            session.add(output, at: frame.timestamp)
        }
    }

    private func finish(with calibration: Calibration?) {
        gaze.stop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        session = nil

        let completion = self.completion
        self.completion = nil
        completion?(calibration)
    }

    private static func makeWindow(for screen: NSScreen, content: some View) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: content)
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}

/// A borderless window that can take key focus, so Escape cancels calibration.
private final class OverlayWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
