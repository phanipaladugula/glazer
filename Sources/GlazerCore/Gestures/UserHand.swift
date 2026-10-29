import CoreGraphics

/// Decides which hand in view, if any, is the user's.
///
/// A camera on a desk often sees other people: someone behind the user, a colleague
/// leaning in. Their hands mustn't take screenshots. A hand counts only if it's where the
/// user's own hand can be, beside or in front of their face, and the right size for a
/// hand that close to the camera. Sizes and distances are measured in the user's face
/// widths and heights, so the rules hold near the camera and far from it.
public enum UserHand {
    /// How far a hand may be beside the middle of the face, in face widths.
    static let sideways = 3.0
    /// How far above the middle of the face it may be, in face heights.
    static let above = 1.5
    /// How far below the middle of the face it may be, in face heights.
    static let below = 2.5
    /// The palm's length as a share of the face's height. A palm is about half a face
    /// long, a little more when the hand is held nearer the camera than the face.
    static let palmToFace: ClosedRange<Double> = 0.2...1.6

    /// The user's hand among `hands`, given where their face is: the nearest to the face
    /// of those that could be theirs.
    public static func hand(of face: CGRect, among hands: [HandReading]) -> HandReading? {
        guard face.width > 0, face.height > 0 else { return nil }
        return
            hands
            .filter { couldBelong($0, to: face) }
            .min { offset(of: $0, from: face).length < offset(of: $1, from: face).length }
    }

    /// Where `hand` is relative to `face`: in face widths across and face heights up from
    /// the middle of the face.
    public static func offset(of hand: HandReading, from face: CGRect) -> CGPoint {
        CGPoint(x: (hand.centre.x - face.midX) / face.width, y: (hand.centre.y - face.midY) / face.height)
    }

    /// The part of the image to search for the user's hand, in normalised image
    /// coordinates. Searching only there finds a distant hand better, because Vision
    /// looks at it in more detail, and keeps out hands elsewhere in the room.
    public static func searchArea(around face: CGRect) -> CGRect {
        let margin = 0.5
        let area = CGRect(
            x: face.midX - face.width * (sideways + margin),
            y: face.midY - face.height * (below + margin),
            width: face.width * (sideways + margin) * 2,
            height: face.height * (above + below + margin * 2))
        return area.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func couldBelong(_ hand: HandReading, to face: CGRect) -> Bool {
        let offset = offset(of: hand, from: face)
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
