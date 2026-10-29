import AVFoundation

/// Whether Glazer may use the camera.
public enum CameraAccess: Equatable, Sendable {
    case notDetermined
    case granted
    /// The user declined. Only System Settings can change this.
    case denied
    /// A device policy blocks the camera, such as parental controls or management.
    case restricted

    public static var current: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    /// Shows the system prompt if the user hasn't been asked yet, and returns the result.
    public static func request() async -> CameraAccess {
        guard current == .notDetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    }
}
