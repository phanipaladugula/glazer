import AppKit
import ApplicationServices
import OSLog

/// Opens a file in its usual app, with its window on a chosen display.
@MainActor
public enum DocumentOpener {
    /// Opens `url` and moves the window it opens to the middle of `display`, shrinking it
    /// to fit if it's too big. Returns whether the window was placed; the file opens
    /// either way.
    @discardableResult
    public static func open(_ url: URL, on display: CGDirectDisplayID) async -> Bool {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let application: NSRunningApplication
        do {
            if let app = workspace.urlForApplication(toOpen: url) {
                application = try await workspace.open([url], withApplicationAt: app, configuration: configuration)
            } else {
                // No app for PNGs: there's no window to place.
                workspace.open(url)
                return false
            }
        } catch {
            Logger.focus.error("Couldn't open \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            return false
        }

        guard AccessibilityAccess.isGranted, let area = visibleArea(of: display) else { return false }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        // Apps take a moment to open a window, longer when they weren't running.
        for attempt in 0..<40 {
            // Most apps report which file a window shows. For those that don't, once the
            // app has had a moment, its focused window is the one it just opened.
            let window =
                window(of: app, showing: url)
                ?? (attempt >= 15 && application.isActive ? app.element(kAXFocusedWindowAttribute) : nil)
            if let window {
                place(window, in: area)
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Logger.focus.info("No window found for \(url.lastPathComponent, privacy: .public)")
        return false
    }

    /// The window of `app` showing `url`, by the document it reports. Window titles are
    /// never read.
    private static func window(of app: AXUIElement, showing url: URL) -> AXUIElement? {
        guard let windows = app.value(of: kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return windows.first { window in
            guard let document = window.string(kAXDocumentAttribute), let documentURL = URL(string: document) else {
                return false
            }
            return documentURL.standardizedFileURL == url.standardizedFileURL
        }
    }

    /// Fits `window` within 90% of `area` and centres it there.
    nonisolated static func placement(of size: CGSize, in area: CGRect) -> CGRect {
        let limit = CGSize(width: area.width * 0.9, height: area.height * 0.9)
        let scale = min(1, limit.width / max(size.width, 1), limit.height / max(size.height, 1))
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return CGRect(
            x: (area.midX - fitted.width / 2).rounded(),
            y: (area.midY - fitted.height / 2).rounded(),
            width: fitted.width,
            height: fitted.height)
    }

    private static func place(_ window: AXUIElement, in area: CGRect) {
        let size = window.frame?.size ?? CGSize(width: area.width * 0.6, height: area.height * 0.6)
        window.setFrame(placement(of: size, in: area))
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// The part of `display` windows may use, without the menu bar and Dock, in Core
    /// Graphics global coordinates (origin at the top left of the main display).
    static func visibleArea(of display: CGDirectDisplayID) -> CGRect? {
        let screens = NSScreen.screens
        guard let main = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first,
            let screen = screens.first(where: { $0.displayID == display })
        else { return nil }
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX, y: main.frame.height - visible.maxY, width: visible.width, height: visible.height)
    }
}

extension NSScreen {
    /// The Core Graphics ID of the display this screen is on.
    public var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
