import CoreVideo
import GlazerCore
import OSLog
import Vision

/// Finds faces in a camera image and measures them, using Apple's Vision framework on
/// this Mac. Nothing leaves the Mac, and the image is not kept.
struct FrameAnalyzer: Sendable {
    /// The most faces given a signature in one frame. Signatures cost more than detection,
    /// and the user is almost always among the nearest few faces.
    private let maximumSignatures = 3

    /// How much to widen a face's box before computing its signature, so the crop
    /// includes the whole face rather than just the eyes, nose and mouth.
    private let signatureCropPadding = 0.15

    func analyze(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval, includeSignatures: Bool) -> Frame {
        let brightness = Self.brightness(of: pixelBuffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        let detection = VNDetectFaceRectanglesRequest()
        detection.revision = VNDetectFaceRectanglesRequestRevision3
        do {
            try handler.perform([detection])
        } catch {
            Logger.vision.error("Face detection failed: \(error)")
            return Frame(timestamp: timestamp, faces: [], brightness: brightness)
        }

        let observations = (detection.results ?? []).sorted { $0.area > $1.area }
        let faces = observations.enumerated().map { index, observation in
            let signature =
                includeSignatures && index < maximumSignatures
                ? signature(for: observation, using: handler)
                : nil
            return DetectedFace(
                bounds: observation.boundingBox,
                pose: HeadPose(
                    yaw: Self.degrees(observation.yaw),
                    pitch: Self.degrees(observation.pitch)
                ),
                confidence: Double(observation.confidence),
                signature: signature
            )
        }
        return Frame(timestamp: timestamp, faces: faces, brightness: brightness)
    }

    /// An image feature print of the face, as a ``FaceSignature``.
    ///
    /// Vision has no public face recognition, so face lock uses a general-purpose image
    /// feature print of a tight crop of the face. See docs/adr/0004.
    private func signature(for face: VNFaceObservation, using handler: VNImageRequestHandler) -> FaceSignature? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFill
        request.regionOfInterest = Self.crop(face.boundingBox, padding: signatureCropPadding)

        do {
            try handler.perform([request])
        } catch {
            Logger.vision.error("Feature print failed: \(error)")
            return nil
        }
        guard let print = request.results?.first, print.elementType == .float else { return nil }

        let values = print.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(print.elementCount))
        }
        return FaceSignature(values: values)
    }

    /// `box` widened by `padding` on each side, kept inside the image.
    private static func crop(_ box: CGRect, padding: Double) -> CGRect {
        box.insetBy(dx: -box.width * padding, dy: -box.height * padding)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func degrees(_ radians: NSNumber?) -> Double {
        (radians?.doubleValue ?? 0) * 180 / .pi
    }

    /// The average of the luma plane, from 0 to 1, sampled on a sparse grid. Sampling
    /// every eighth pixel is plenty for an average and keeps this cheap.
    static func brightness(of pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return 0 }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        let step = 8

        var total = 0
        var count = 0
        for y in stride(from: 0, to: height, by: step) {
            let row = luma + y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                total += Int(row[x])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) / 255 : 0
    }
}

extension VNFaceObservation {
    fileprivate var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

extension Logger {
    static let vision = Logger(subsystem: "io.github.phanipaladugula.glazer", category: "vision")
}
