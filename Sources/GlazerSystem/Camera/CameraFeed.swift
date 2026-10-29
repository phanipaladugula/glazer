import AVFoundation
import GlazerCore
import OSLog
import os

/// Reads frames from the camera and turns each into a ``Frame``.
///
/// Frames are analysed on a background queue as they arrive and then dropped. No image
/// is ever written anywhere or kept after its analysis. Analysis runs at most
/// ``framesPerSecond`` times a second, which is plenty for head movements and keeps the
/// CPU cost low.
public final class CameraFeed: NSObject, @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case noCamera
        case cannotOpenCamera
        /// The camera stopped while running: it was disconnected, or the system stopped it.
        case interrupted
    }

    /// The capture session, for showing a live preview during face lock setup. Glazer
    /// never records from it.
    public let session = AVCaptureSession()

    /// The most frames analysed per second.
    public let framesPerSecond: Double

    // Session configuration runs on `sessionQueue`; frames arrive on `outputQueue`.
    // Shared state between them and callers is protected by `state`.
    private let sessionQueue = DispatchQueue(label: "io.github.phanipaladugula.glazer.camera.session")
    private let outputQueue = DispatchQueue(
        label: "io.github.phanipaladugula.glazer.camera.output", qos: .userInitiated)
    private let analyzer = FrameAnalyzer()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var onFrame: (@Sendable (Frame) -> Void)?
        var onStop: (@Sendable (Failure) -> Void)?
        /// The unique ID of the camera the session uses.
        var deviceID: String?
        var wantsSignatures = false
        var lastAnalysis: TimeInterval = -.infinity
        var isConfigured = false
    }

    public init(framesPerSecond: Double = 12) {
        self.framesPerSecond = framesPerSecond
        super.init()

        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionFailed(_:)), name: AVCaptureSession.runtimeErrorNotification,
            object: session)
        center.addObserver(
            self, selector: #selector(deviceDisconnected(_:)), name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil)
    }

    /// Starts the camera and calls `onFrame` on a background queue for each analysed
    /// frame. If the camera later stops by itself, `onStop` is called once, with why.
    /// Calling it again replaces both handlers.
    public func start(
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable (Failure) -> Void = { _ in }
    ) async throws {
        state.withLock {
            $0.onFrame = onFrame
            $0.onStop = onStop
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops the camera. The system's camera indicator turns off.
    public func stop() {
        state.withLock {
            $0.onFrame = nil
            $0.onStop = nil
        }
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Whether frames should include face signatures. They cost more to compute, so
    /// they are only produced when face lock needs them.
    public func setWantsSignatures(_ wantsSignatures: Bool) {
        state.withLock { $0.wantsSignatures = wantsSignatures }
    }

    /// Sets up the session with the preferred camera, or rebuilds it when the camera it
    /// was using has gone away.
    private func configureIfNeeded() throws {
        let current = state.withLock { $0.isConfigured ? $0.deviceID : nil }
        if let current, AVCaptureDevice(uniqueID: current)?.isConnected == true {
            return
        }

        guard let device = Self.preferredCamera() else { throw Failure.noCamera }
        guard let input = try? AVCaptureDeviceInput(device: device) else { throw Failure.cannotOpenCamera }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Start from an empty session, so a failed or stale setup can't block this one.
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        state.withLock {
            $0.isConfigured = false
            $0.deviceID = nil
        }

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        guard session.canAddInput(input) else { throw Failure.cannotOpenCamera }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw Failure.cannotOpenCamera
        }
        session.addOutput(output)

        let deviceID = device.uniqueID
        state.withLock {
            $0.isConfigured = true
            $0.deviceID = deviceID
        }
        Logger.camera.info("Camera configured: \(device.localizedName, privacy: .public)")
    }

    @objc private func sessionFailed(_ notification: Notification) {
        Logger.camera.error("Camera session failed: \(String(describing: notification.userInfo))")
        reportStop(.interrupted)
    }

    @objc private func deviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        let deviceID = device.uniqueID
        guard state.withLock({ $0.deviceID == deviceID }) else { return }
        Logger.camera.info("Camera disconnected: \(device.localizedName, privacy: .public)")
        reportStop(.interrupted)
    }

    /// Calls the stop handler once, if the camera is running.
    private func reportStop(_ failure: Failure) {
        let handler = state.withLock { state -> (@Sendable (Failure) -> Void)? in
            defer { state.onStop = nil }
            return state.onFrame == nil ? nil : state.onStop
        }
        handler?(failure)
    }

    /// The built-in camera if there is one, otherwise the system's default.
    private static func preferredCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? AVCaptureDevice.default(for: .video)
    }
}

extension CameraFeed: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let minimumInterval = 1 / framesPerSecond

        let job = state.withLock { state -> (handler: @Sendable (Frame) -> Void, signatures: Bool)? in
            guard let handler = state.onFrame, timestamp - state.lastAnalysis >= minimumInterval else { return nil }
            state.lastAnalysis = timestamp
            return (handler, state.wantsSignatures)
        }
        guard let job, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frame = analyzer.analyze(pixelBuffer, at: timestamp, includeSignatures: job.signatures)
        job.handler(frame)
    }
}

extension Logger {
    static let camera = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "camera")
}
