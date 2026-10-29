import AppKit
import GlazerCore
import GlazerSystem
import OSLog

/// Turns hand gestures into screenshots: a grab takes one of the display the user faces,
/// and the drop pastes it where the pointer is, or opens it on the display they face then.
///
/// A grab saves the screenshot where macOS saves its own and copies it to the clipboard,
/// as ⌃⇧⌘3 does, so it's kept even if the drop never comes.
@MainActor
final class GrabController {
    struct Screenshot {
        let url: URL
        let image: CGImage
        let png: Data
    }

    private let overlay = GrabOverlay()
    /// The screenshot being taken or held, from the grab until the drop or a cancel.
    private var held: Task<Screenshot?, Never>?
    /// The display the user faces now, where the held screenshot follows them.
    private var facing: Display.ID?

    var isHolding: Bool {
        held != nil
    }

    func handle(_ gesture: GazeController.Gesture) {
        switch gesture {
        case .grabbed(let display): grab(display)
        case .dropped(let display): drop(on: display)
        case .cancelled: cancel()
        }
    }

    /// Moves the held screenshot's thumbnail to `display`, as the user turns to it.
    func facingChanged(to display: Display.ID?) {
        facing = display
        guard isHolding, let display, let frame = frame(of: display) else { return }
        overlay.moveThumbnail(to: frame)
    }

    private func grab(_ display: Display.ID) {
        guard held == nil else { return }
        held = Task {
            do {
                let image = try await ScreenCapture.image(of: display)
                // Encoding and writing a 5K screenshot takes a moment; keep it off the main
                // thread so the pointer never stutters.
                let (png, url) = try await Task.detached(priority: .userInitiated) {
                    let png = try ScreenshotStore.png(image)
                    return (png, try ScreenshotStore.save(png: png))
                }.value
                ScreenshotStore.copy(image, png: png)
                GrabFeedback.playShutter()
                if let screen = screen(of: display) {
                    overlay.flash(screen.frame)
                }
                // The user may already have let go, or turned elsewhere, while it saved.
                if held != nil, let frame = frame(of: facing ?? display) {
                    overlay.showThumbnail(image, on: frame)
                }
                Logger.gestures.info("Grabbed display \(display, privacy: .public)")
                return Screenshot(url: url, image: image, png: png)
            } catch {
                Logger.gestures.error("Grab failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
                held = nil
                return nil
            }
        }
    }

    private func drop(on display: Display.ID) {
        guard let held else { return }
        self.held = nil
        overlay.hideThumbnail()
        Task {
            guard let screenshot = await held.value else { return }
            let pointer = CGEvent(source: nil)?.location ?? .zero
            let pointerDisplay = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?
                .displayID
            if pointerDisplay == display, await PasteTarget.acceptsPaste(at: pointer) {
                // Something else may have been copied since the grab.
                ScreenshotStore.copy(screenshot.image, png: screenshot.png)
                await PasteTarget.paste(at: pointer)
                Logger.gestures.info("Pasted on display \(display, privacy: .public)")
            } else {
                await DocumentOpener.open(screenshot.url, on: display)
                Logger.gestures.info("Opened on display \(display, privacy: .public)")
            }
        }
    }

    private func cancel() {
        held = nil
        overlay.hideThumbnail()
    }

    private func screen(of display: Display.ID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == display }
    }

    /// The part of `display` windows may use, in AppKit screen coordinates.
    private func frame(of display: Display.ID) -> CGRect? {
        screen(of: display)?.visibleFrame
    }
}

/// The sound macOS plays for a screenshot, when interface sounds are on.
enum GrabFeedback {
    private static let shutter = NSSound(
        contentsOfFile:
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)

    @MainActor
    static func playShutter() {
        // System Settings › Sound › Play user interface sound effects.
        let enabled = UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Int ?? 1
        guard enabled != 0 else { return }
        shutter?.stop()
        shutter?.play()
    }
}

extension Logger {
    static let gestures = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "gestures")
}
