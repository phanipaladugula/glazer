import CoreGraphics
import Foundation

/// The joints of one hand, as Vision found them, in pixels of the camera image.
///
/// Pixels rather than normalised coordinates, because the camera image isn't square: in
/// normalised coordinates a finger pointing sideways would look shorter than one pointing
/// up.
public struct HandJoints: Equatable, Sendable {
    /// One finger, from the knuckle (where it meets the palm) to the tip.
    public struct Finger: Equatable, Sendable {
        public var knuckle: CGPoint
        public var middle: CGPoint
        public var top: CGPoint
        public var tip: CGPoint

        public init(knuckle: CGPoint, middle: CGPoint, top: CGPoint, tip: CGPoint) {
            self.knuckle = knuckle
            self.middle = middle
            self.top = top
            self.tip = tip
        }
    }

    public var wrist: CGPoint
    /// The fingers Vision found, of index, middle, ring and little. The thumb is left
    /// out: it moves much the same in an open hand and a fist.
    public var fingers: [Finger]

    public init(wrist: CGPoint, fingers: [Finger]) {
        self.wrist = wrist
        self.fingers = fingers
    }

    /// The fewest fingers that give a trustworthy reading.
    public static let minimumFingers = 3

    /// The length of the palm: the typical distance from the wrist to a knuckle. Every
    /// other length is measured against it, so readings don't change with how far the
    /// hand is from the camera.
    public var palmLength: Double {
        let lengths = fingers.map { wrist.distance(to: $0.knuckle) }
        return lengths.isEmpty ? 0 : lengths.reduce(0, +) / Double(lengths.count)
    }

    /// The hand's shape, or `nil` if too little of it was found to tell.
    public var features: HandFeatures? {
        let palm = palmLength
        guard fingers.count >= Self.minimumFingers, palm > 1 else { return nil }

        let reaches = fingers.map { wrist.distance(to: $0.tip) / palm }
        let curls = fingers.map { finger in
            (Self.bend(finger.knuckle, finger.middle, finger.top) + Self.bend(finger.middle, finger.top, finger.tip))
                / .pi
        }
        let centre = CGPoint(
            x: (fingers.map(\.knuckle.x).reduce(wrist.x, +)) / CGFloat(fingers.count + 1),
            y: (fingers.map(\.knuckle.y).reduce(wrist.y, +)) / CGFloat(fingers.count + 1)
        )
        let spreads = fingers.map { centre.distance(to: $0.tip) / palm }

        return HandFeatures(
            reach: Statistics.median(reaches),
            curl: curls.reduce(0, +) / Double(curls.count),
            spread: spreads.reduce(0, +) / Double(spreads.count)
        )
    }

    /// How far the finger turns at `joint`, in radians: 0 when `before`, `joint` and
    /// `after` lie in a straight line, π when it folds right back.
    static func bend(_ before: CGPoint, _ joint: CGPoint, _ after: CGPoint) -> Double {
        let incoming = CGVector(dx: joint.x - before.x, dy: joint.y - before.y)
        let outgoing = CGVector(dx: after.x - joint.x, dy: after.y - joint.y)
        let lengths = incoming.length * outgoing.length
        guard lengths > 0 else { return 0 }
        let cosine = (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) / lengths
        return acos(min(max(Double(cosine), -1), 1))
    }
}

/// Three measures of how open a hand is. Each is unitless, so it doesn't depend on how
/// far away the hand is, and each fails differently: a fist seen from the side still
/// curls, and an open hand tilted away from the camera still reaches.
public struct HandFeatures: Codable, Equatable, Sendable {
    /// How far the fingertips are from the wrist, in palm lengths. About 1.9 for an open
    /// hand and 1 for a fist.
    public var reach: Double
    /// How much the fingers bend at their two upper joints together, from 0 (straight) to
    /// 1 (folded right back). About 0.1 for an open hand and 0.9 for a fist.
    public var curl: Double
    /// How far the fingertips are from the middle of the palm, in palm lengths.
    public var spread: Double

    public init(reach: Double, curl: Double, spread: Double) {
        self.reach = reach
        self.curl = curl
        self.spread = spread
    }

    var values: [Double] {
        [reach, curl, spread]
    }

    init(values: [Double]) {
        self.init(reach: values[0], curl: values[1], spread: values[2])
    }
}

/// A hand found in a camera frame.
public struct HandReading: Equatable, Sendable {
    public let features: HandFeatures
    /// The middle of the palm, in normalised image coordinates (0–1 on both axes).
    public let centre: CGPoint
    /// The palm's length as a share of the image height. Nearer hands are bigger.
    public let size: Double
    /// How sure Vision is that this is a hand, from 0 to 1.
    public let confidence: Double

    public init(features: HandFeatures, centre: CGPoint, size: Double, confidence: Double) {
        self.features = features
        self.centre = centre
        self.size = size
        self.confidence = confidence
    }
}

enum Statistics {
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The median absolute deviation, scaled to match a standard deviation for normally
    /// distributed values. Unlike a standard deviation, a few misread frames barely move it.
    static func deviation(_ values: [Double]) -> Double {
        let centre = median(values)
        return median(values.map { abs($0 - centre) }) * 1.4826
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        Double(hypot(x - other.x, y - other.y))
    }
}

extension CGVector {
    fileprivate var length: CGFloat {
        hypot(dx, dy)
    }
}
