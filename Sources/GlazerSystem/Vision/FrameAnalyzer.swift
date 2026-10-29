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

    /// How much to widen a face's box before computing its signature. None: tested on
    /// real portraits, the exact box separated people best, because any wider crop lets
    /// hair, clothes and background, which aren't who someone is, sway the comparison.
    private let signatureCropPadding = 0.0

    /// The least share of the image height a palm must cover to be read. Smaller hands are
    /// usually someone further back, and their joints are too few pixels apart to trust.
    static let minimumPalmSize = 0.04

    /// The least confidence for a joint to be used. Low, because in a fist the fingertips
    /// are hidden behind the knuckles and Vision places them with little confidence, yet
    /// roughly in the right place, which is all the shape measures need.
    static let minimumJointConfidence: VNConfidence = 0.1

    func analyze(
        _ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval, includeSignatures: Bool, includeHands: Bool = false
    ) -> Frame {
        let brightness = Self.brightness(of: pixelBuffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        let detection = VNDetectFaceRectanglesRequest()
        detection.revision = VNDetectFaceRectanglesRequestRevision3
        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 2
        do {
            // One call, so Vision can share work between the two.
            try handler.perform(includeHands ? [detection, hands] : [detection])
        } catch {
            Logger.vision.error("Face or hand detection failed: \(error)")
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
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let hand = includeHands ? Self.nearestHand(in: hands.results ?? [], imageSize: size) : nil
        return Frame(timestamp: timestamp, faces: faces, brightness: brightness, hand: hand)
    }

    /// The biggest readable hand, which is almost always the user's raised one.
    static func nearestHand(in observations: [VNHumanHandPoseObservation], imageSize: CGSize) -> HandReading? {
        observations
            .compactMap { reading(of: $0, imageSize: imageSize) }
            .filter { $0.size >= minimumPalmSize }
            .max { $0.size < $1.size }
    }

    private static let fingerJoints: [[VNHumanHandPoseObservation.JointName]] = [
        [.indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    private static func reading(of observation: VNHumanHandPoseObservation, imageSize: CGSize) -> HandReading? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        // Vision's points are normalised with the origin at the bottom left. Pixels keep
        // lengths true whatever the image's shape.
        func pixel(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let point = points[name], point.confidence >= minimumJointConfidence else { return nil }
            return CGPoint(x: point.location.x * imageSize.width, y: point.location.y * imageSize.height)
        }

        guard let wrist = pixel(.wrist) else { return nil }
        let fingers = fingerJoints.compactMap { names -> HandJoints.Finger? in
            let joints = names.compactMap(pixel)
            guard joints.count == 4 else { return nil }
            return HandJoints.Finger(knuckle: joints[0], middle: joints[1], top: joints[2], tip: joints[3])
        }
        let hand = HandJoints(wrist: wrist, fingers: fingers)
        guard let features = hand.features, imageSize.height > 0 else { return nil }

        let knuckles = fingers.map(\.knuckle) + [wrist]
        let centre = CGPoint(
            x: knuckles.map(\.x).reduce(0, +) / CGFloat(knuckles.count) / imageSize.width,
            y: knuckles.map(\.y).reduce(0, +) / CGFloat(knuckles.count) / imageSize.height
        )
        return HandReading(
            features: features,
            centre: centre,
            size: hand.palmLength / Double(imageSize.height),
            confidence: Double(observation.confidence)
        )
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
