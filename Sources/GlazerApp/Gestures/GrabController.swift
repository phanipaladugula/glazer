import AppKit
import GlazerCore
import GlazerSystem
import OSLog

/// Turns hand gestures into screenshots: a grab takes one of the display the user faces,
/// and the drop pastes it where the pointer is, or shows it on the display they face then.
///
/// A grab saves the screenshot where macOS saves its own and copies it to the clipboard,
/// as ⌃⇧⌘3 does, so it's kept even if the drop never comes.
@MainActor
final class GrabController {
    struct Screenshot {
        let url: URL
        let image: CGImage
        let png: Data
        /// The clipboard's change count once the screenshot was copied.
        let copied: Int
    }

    private let overlay = GrabOverlay()
    private let windows = ScreenshotWindows()
    /// Told when a screenshot was taken, which proves Screen Recording is allowed.
    var onCaptured: (() -> Void)?
    /// Told when macOS refused the screenshot because Screen Recording isn't allowed.
    var onNotAllowed: (() -> Void)?
    /// The screenshot being taken or held, from the grab until the drop or a cancel.
    private var held: Task<Screenshot?, Never>?
    /// The display the user faces now, where the held screenshot follows them.
    private var facing: Display.ID?
    /// While a grab is held, gets the app under the pointer ready to take a paste.
    private var preparing: Task<Void, Never>?

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

    /// Asks the app under the pointer, every moment while a grab is held, to describe its
    /// content, so the drop can paste without waiting for it.
    private func startPreparing() {
        preparing?.cancel()
        preparing = Task {
            while !Task.isCancelled {
                if let pointer = CGEvent(source: nil)?.location {
                    PasteTarget.prepare(at: pointer)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func stopPreparing() {
        preparing?.cancel()
        preparing = nil
    }

    private func grab(_ display: Display.ID) {
        guard held == nil else { return }
        startPreparing()
        held = Task {
            do {
                let image = try await ScreenCapture.image(of: display)
                // Encoding and writing a 5K screenshot takes a moment; keep it off the main
                // thread so the pointer never stutters.
                let (png, url) = try await Task.detached(priority: .userInitiated) {
                    let png = try ScreenshotStore.png(image)
                    return (png, try ScreenshotStore.save(png: png))
                }.value
                let copied = ScreenshotStore.copy(png: png)
                onCaptured?()
                GrabFeedback.playShutter()
                if let screen = screen(of: display) {
                    overlay.flash(screen.frame)
                }
                // The user may already have let go, or turned elsewhere, while it saved.
                if held != nil, let frame = frame(of: facing ?? display) {
                    overlay.showThumbnail(image, on: frame)
                }
                Logger.gestures.notice("Grabbed display \(display, privacy: .public)")
                return Screenshot(url: url, image: image, png: png, copied: copied)
            } catch {
                Logger.gestures.error("Grab failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
                held = nil
                stopPreparing()
                // Say why where the user is looking, rather than failing silently.
                if let frame = frame(of: display) {
                    if case .notAllowed = error as? ScreenCapture.Failure {
                        onNotAllowed?()
                        overlay.showMessage(
                            "Glazer needs Screen Recording to take screenshots. Allow it in System Settings, "
                                + "then reopen Glazer.", on: frame)
                    } else {
                        overlay.showMessage("The screenshot couldn't be taken. Try again.", on: frame)
                    }
                }
                return nil
            }
        }
    }

    private func drop(on display: Display.ID) {
        guard let held else { return }
        self.held = nil
        stopPreparing()
        overlay.hideThumbnail()
        let droppedAt = ContinuousClock.now
        Task {
            guard let screenshot = await held.value else { return }
            // Something else may have been copied since the grab.
            if !ScreenshotStore.stillCopied(screenshot.copied) {
                ScreenshotStore.copy(png: screenshot.png)
            }

            let pointer = CGEvent(source: nil)?.location ?? .zero
            let pointerDisplay = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?
                .displayID
            if pointerDisplay == display, let target = await PasteTarget.find(at: pointer) {
                await PasteTarget.paste(at: pointer)
                let elapsed = ContinuousClock.now - droppedAt
                let milliseconds = Int(elapsed / .milliseconds(1))
                Logger.gestures.notice(
                    "Pasted into \(target, privacy: .public) on display \(display, privacy: .public) \(milliseconds, privacy: .public) ms after the drop"
                )
                return
            }
            // The pointer isn't on a text box there, but the typing cursor may be: in the
            // message box of the chat the user is looking at, say.
            if let target = PasteTarget.focusedTextBox(in: CGDisplayBounds(display)) {
                PasteTarget.pasteAtFocus()
                Logger.gestures.notice(
                    "Pasted into focused \(target, privacy: .public) on display \(display, privacy: .public)")
                return
            }
            let pointerName = pointerDisplay.map { String($0) } ?? "none"
            Logger.gestures.notice(
                "Showing on display \(display, privacy: .public); pointer on \(pointerName, privacy: .public)")
            if let screen = screen(of: display) ?? NSScreen.main {
                windows.show(screenshot.image, file: screenshot.url, on: screen)
            }
        }
    }

    private func cancel() {
        if held != nil {
            Logger.gestures.notice("Grab cancelled: held too long, or the hand went out of view")
        }
        held = nil
        stopPreparing()
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
