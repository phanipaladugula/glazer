import CoreGraphics
import Foundation

/// What Glazer learned from one camera frame. The image itself is never kept.
public struct Frame: Sendable {
    /// Seconds on a monotonic clock. Only differences between frames are meaningful.
    public let timestamp: TimeInterval

    /// Every face found in the frame.
    public let faces: [DetectedFace]

    /// The average brightness of the frame, from 0 (black) to 1 (white).
    public let brightness: Double

    public init(timestamp: TimeInterval, faces: [DetectedFace], brightness: Double) {
        self.timestamp = timestamp
        self.faces = faces
        self.brightness = brightness
    }
}

/// A face found in a camera frame.
public struct DetectedFace: Equatable, Sendable {
    /// The face's bounding box in normalised image coordinates (0–1 on both axes).
    public let bounds: CGRect

    public let pose: HeadPose

    /// How sure the detector is that this is a face, from 0 to 1.
    public let confidence: Double

    /// A numeric description of the face, used for face lock. Present only on frames
    /// where the tracker asked for one, because computing it is relatively expensive.
    public let signature: FaceSignature?

    public init(bounds: CGRect, pose: HeadPose, confidence: Double, signature: FaceSignature? = nil) {
        self.bounds = bounds
        self.pose = pose
        self.confidence = confidence
        self.signature = signature
    }

    /// The share of the image the face covers. Nearer faces cover more.
    public var area: Double {
        Double(bounds.width * bounds.height)
    }
}

extension CGRect {
    /// Intersection over union: 1 for identical rectangles, 0 for disjoint ones.
    func overlap(with other: CGRect) -> Double {
        let intersection = self.intersection(other)
        guard !intersection.isNull else { return 0 }
        let shared = intersection.width * intersection.height
        let union = width * height + other.width * other.height - shared
        return union > 0 ? Double(shared / union) : 0
    }
}
