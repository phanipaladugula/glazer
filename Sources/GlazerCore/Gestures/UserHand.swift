import CoreGraphics

/// Decides which hand in view, if any, is the user's.
///
/// A camera on a desk often sees other people: someone behind the user, a colleague
/// leaning in. Their hands mustn't take screenshots. A hand counts only if it's where the
/// user's own hand can be, beside or in front of their face, and the right size for a
/// hand that close to the camera. Distances and sizes are measured in the height of the
/// user's face, so the rules hold near the camera and far from it, and as the user turns
/// their head: a face turned towards another display looks narrower, but no shorter.
public enum UserHand {
    /// How far a hand may be beside the middle of the face, in face heights.
    static let sideways = 2.6
    /// How far above the middle of the face it may be, in face heights.
    static let above = 1.5
    /// How far below the middle of the face it may be, in face heights.
    static let below = 2.5
    /// The palm's length as a share of the face's height. A palm is about half a face
    /// long, a little more when the hand is held nearer the camera than the face.
    static let palmToFace: ClosedRange<Double> = 0.2...1.6

    /// The user's hand among `hands`, given where their face is: the nearest to the face
    /// of those that could be theirs. `aspectRatio` is the image's width over its height.
    public static func hand(of face: CGRect, among hands: [HandReading], aspectRatio: Double) -> HandReading? {
        guard face.height > 0 else { return nil }
        return
            hands
            .filter { couldBelong($0, to: face, aspectRatio: aspectRatio) }
            .min {
                offset(of: $0, from: face, aspectRatio: aspectRatio).length
                    < offset(of: $1, from: face, aspectRatio: aspectRatio).length
            }
    }

    /// Where `hand` is relative to `face`, in face heights across and up from the middle
    /// of the face.
    public static func offset(of hand: HandReading, from face: CGRect, aspectRatio: Double) -> CGPoint {
        CGPoint(
            x: (hand.centre.x - face.midX) * aspectRatio / face.height,
            y: (hand.centre.y - face.midY) / face.height)
    }

    /// The part of the image to search for the user's hand, in normalised image
    /// coordinates. Searching only there finds a distant hand better, because Vision
    /// looks at it in more detail, and keeps out hands elsewhere in the room.
    public static func searchArea(around face: CGRect, aspectRatio: Double) -> CGRect {
        let margin = 0.5
        let halfWidth = face.height * (sideways + margin) / aspectRatio
        let area = CGRect(
            x: face.midX - halfWidth,
            y: face.midY - face.height * (below + margin),
            width: halfWidth * 2,
            height: face.height * (above + below + margin * 2))
        return area.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The hand in `hands` that's most likely `previous` moved on a frame: near where it
    /// was and about the same size. While a grab is held, this keeps following the hand
    /// that grabbed even when the face goes out of view, such as when the user turns far.
    public static func hand(continuing previous: HandReading, among hands: [HandReading]) -> HandReading? {
        hands
            .filter { hand in
                let ratio = hand.size / max(previous.size, 0.001)
                return hand.centre.distance(to: previous.centre) <= 0.25 && ratio >= 0.6 && ratio <= 1.6
            }
            .min { $0.centre.distance(to: previous.centre) < $1.centre.distance(to: previous.centre) }
    }

    private static func couldBelong(_ hand: HandReading, to face: CGRect, aspectRatio: Double) -> Bool {
        let offset = offset(of: hand, from: face, aspectRatio: aspectRatio)
        let palmToFace = hand.size / Double(face.height)
        return abs(offset.x) <= sideways && offset.y <= above && offset.y >= -below
            && Self.palmToFace.contains(palmToFace)
    }
}

extension CGPoint {
    var length: Double {
        Double(hypot(x, y))
    }
}
