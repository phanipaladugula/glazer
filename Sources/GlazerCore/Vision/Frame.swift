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

    /// Every readable hand in view, biggest first, on frames where hands were looked for:
    /// only while hand gestures are on, because finding them costs about as much as
    /// finding faces. Which one is the user's is decided with ``UserHand``.
    public let hands: [HandReading]

    /// The image's width divided by its height, to compare distances across and up.
    public let aspectRatio: Double

    public init(
        timestamp: TimeInterval, faces: [DetectedFace], brightness: Double, hands: [HandReading] = [],
        aspectRatio: Double = 16.0 / 9.0
    ) {
        self.timestamp = timestamp
        self.faces = faces
        self.brightness = brightness
        self.hands = hands
        self.aspectRatio = aspectRatio
    }

    /// The biggest face, which is the user's while nobody else is in view, such as during
    /// calibration.
    public var nearestFace: DetectedFace? {
        faces.max { $0.area < $1.area }
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
