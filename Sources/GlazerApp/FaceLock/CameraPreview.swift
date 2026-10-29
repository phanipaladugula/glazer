import AVFoundation
import SwiftUI

/// A live, mirrored view of the camera, for face lock setup. It shows the capture
/// session's frames on screen and nothing else: it doesn't record.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
        }

        required init?(coder: NSCoder) {
            fatalError("PreviewView is created in code only")
        }

        override func layout() {
            super.layout()
            // Mirror like a reflection, so turning left moves the face left on screen.
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}
