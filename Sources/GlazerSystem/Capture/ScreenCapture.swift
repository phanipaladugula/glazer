import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit

/// Whether Glazer may capture the screen, which hand gestures need to take screenshots.
public enum ScreenCaptureAccess {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt that leads to System Settings › Privacy & Security ›
    /// Screen & System Audio Recording. macOS shows it only once per app; after that, use
    /// ``SystemSettings/open(_:)``.
    public static func request() {
        CGRequestScreenCaptureAccess()
    }
}

/// Takes a screenshot of one display.
public enum ScreenCapture {
    public enum Failure: Error, Equatable {
        case notAllowed
        case displayNotFound
        case failed(String)
    }

    /// An image of everything on `displayID` at full resolution, without the pointer and
    /// without Glazer's own windows.
    @MainActor
    public static func image(of displayID: CGDirectDisplayID) async throws(Failure) -> CGImage {
        guard ScreenCaptureAccess.isGranted else { throw .notAllowed }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw Failure.displayNotFound
            }
            let ownProcess = ProcessInfo.processInfo.processIdentifier
            let filter = SCContentFilter(
                display: display,
                excludingApplications: content.applications.filter { $0.processID == ownProcess },
                exceptingWindows: [])

            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch let failure as Failure {
            throw failure
        } catch {
            Logger.capture.error("Screenshot failed: \(error, privacy: .public)")
            throw .failed(error.localizedDescription)
        }
    }
}

extension Logger {
    static let capture = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "capture")
}
