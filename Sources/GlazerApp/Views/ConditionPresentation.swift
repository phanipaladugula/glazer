import GlazerCore
import SwiftUI

/// How an ``AppModel/Condition`` looks and reads in the menu bar and the panel. Copy
/// follows `docs/design/README.md`: say what is happening, not how it works.
struct ConditionPresentation {
    enum Action {
        case openSetup
        case openCameraSettings
        case calibrate
        case retryFaceLock
        case retryCamera
        case openAccessibilitySettings
    }

    /// The panel's status line.
    let status: String
    /// The menu bar symbol.
    let symbol: String
    /// Whether the header badge is filled with the accent colour.
    let isActive: Bool
    /// Something the user should do, shown as a card in the panel.
    let callout: (text: String, button: String, action: Action)?

    init(_ condition: AppModel.Condition) {
        switch condition {
        case .off:
            self.init("Off. Camera is not in use", symbol: "eye.slash", active: false)
        case .calibrating:
            self.init("Calibrating…", symbol: "eye", active: true)
        case .enrollingFace:
            self.init("Setting up face lock…", symbol: "eye", active: true)
        case .running(.following):
            self.init("Following your gaze", symbol: "eye", active: true)
        case .running(.searching):
            self.init("Looking for you", symbol: "eye", active: true)
        case .running(.tooDark):
            self.init(
                "Too dark to see you", symbol: "eye.trianglebadge.exclamationmark", active: true,
                callout: nil)
        case .running(.notRecognized):
            self.init("Face not recognised", symbol: "eye", active: true)
        case .listening(let key):
            self.init("Press \(key.shortName) twice to switch", symbol: "keyboard", active: true)
        case .attention(.setupNeeded):
            self.init(
                "Not set up yet", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: (
                    "Choose how to switch displays, and Glazer walks you through the rest.", "Set Up…", .openSetup
                ))
        case .attention(.cameraDenied):
            self.init(
                "Camera access is off", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: (
                    "Glazer needs the camera to see which display you're facing.", "Open Settings…",
                    .openCameraSettings
                ))
        case .attention(.cameraUnavailable):
            self.init(
                "Camera unavailable", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: (
                    "The camera stopped or couldn't start. It may be disconnected or in use by another app.",
                    "Try Again", .retryCamera
                ))
        case .attention(.secondDisplayNeeded):
            self.init("Waiting for a second display", symbol: "eye", active: false)
        case .attention(.faceLockUnavailable):
            self.init(
                "Face lock paused", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: (
                    "Glazer couldn't read your face lock from the Keychain, so it's paused rather than "
                        + "following just anyone.", "Try Again", .retryFaceLock
                ))
        case .attention(.accessibilityNeeded):
            self.init(
                "Needs Accessibility", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: (
                    "Glazer needs Accessibility to move your typing to the display you switch to. If Glazer is "
                        + "already listed, switch it off and on again.", "Open Settings…", .openAccessibilitySettings
                ))
        case .attention(.calibrationNeeded):
            self.init(
                "Displays not calibrated", symbol: "eye.trianglebadge.exclamationmark", active: false,
                callout: ("Look at each display once so Glazer can tell them apart.", "Calibrate…", .calibrate))
        }
    }

    private init(
        _ status: String, symbol: String, active: Bool,
        callout: (text: String, button: String, action: Action)? = nil
    ) {
        self.status = status
        self.symbol = symbol
        self.isActive = active
        self.callout = callout
    }
}
