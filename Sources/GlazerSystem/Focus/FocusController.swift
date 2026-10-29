import AppKit
import ApplicationServices
import GlazerCore
import OSLog

/// Moves the pointer and keyboard focus to another display.
///
/// The window that gets focus is the frontmost window on that display: macOS already
/// keeps windows in the order they were last used, so that is the window the user was
/// last working in there. The pointer goes back to where it was when the user last left
/// that display.
@MainActor
public final class FocusController {
    /// Where the pointer was on each display, in global coordinates with the origin at
    /// the top left of the main display (Core Graphics' convention).
    private var pointerPositions: [Display.ID: CGPoint] = [:]

    public init() {}

    /// Moves focus to `display`. Does nothing while a mouse button is held, so a drag is
    /// never interrupted.
    public func focus(_ display: Display.ID, leaving previous: Display.ID?) {
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let pointer = Self.pointerLocation()
        if let previous {
            pointerPositions[previous] = pointer
        }

        let bounds = CGDisplayBounds(display)
        let window = Self.frontmostWindow(on: bounds)
        if let window {
            activate(window)
        }

        let target =
            pointerPositions[display].flatMap { bounds.contains($0) ? $0 : nil }
            ?? window.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
            ?? CGPoint(x: bounds.midX, y: bounds.midY)
        CGWarpMouseCursorPosition(target)
        // Without this, the pointer pauses for a moment after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Records the pointer's position for its current display, such as when the user
    /// moves it there by hand.
    public func rememberPointer(on display: Display.ID) {
        pointerPositions[display] = Self.pointerLocation()
    }

    // MARK: Windows

    struct WindowInfo {
        let processID: pid_t
        let bounds: CGRect
    }

    /// The frontmost ordinary window whose centre is on the display with `displayBounds`.
    ///
    /// Reading window positions and owners needs no permission. Window titles, which
    /// would need Screen Recording permission, are never read.
    static func frontmostWindow(on displayBounds: CGRect) -> WindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier

        // The list is ordered front to back.
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let processID = window[kCGWindowOwnerPID as String] as? pid_t,
                processID != ownProcess,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.width >= 80, bounds.height >= 60,
                displayBounds.contains(CGPoint(x: bounds.midX, y: bounds.midY))
            else { continue }
            return WindowInfo(processID: processID, bounds: bounds)
        }
        return nil
    }

    /// Brings `window` to the front and makes it key.
    ///
    /// With Accessibility access, the exact window is raised and its app made frontmost.
    /// Without it, the app is asked to activate, which macOS may decline.
    private func activate(_ window: WindowInfo) {
        guard AccessibilityAccess.isGranted else {
            NSRunningApplication(processIdentifier: window.processID)?.activate()
            return
        }

        let application = AXUIElementCreateApplication(window.processID)
        if let element = Self.accessibilityWindow(of: application, matching: window.bounds) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        let result = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if result != .success {
            Logger.focus.error("Could not bring app \(window.processID) to the front: \(result.rawValue)")
        }
    }

    /// The Accessibility element of `application`'s window whose frame matches `bounds`.
    private static func accessibilityWindow(of application: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return nil }

        return windows.first { window in
            guard let frame = frame(of: window) else { return false }
            return abs(frame.minX - bounds.minX) < 2 && abs(frame.minY - bounds.minY) < 2
                && abs(frame.width - bounds.width) < 2 && abs(frame.height - bounds.height) < 2
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue, let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        // The type IDs were checked above, so these downcasts are safe.
        AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position)
        AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// The pointer's location in Core Graphics global coordinates.
    private static func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}

extension Logger {
    static let focus = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "focus")
}
