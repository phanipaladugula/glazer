import CoreGraphics
import Foundation

@testable import GlazerCore

/// A hand drawn in pixels, wrist at `wrist`, with four fingers pointing up and each bent
/// by `bend` radians at both upper joints. 0 is an open hand; about 1.4 is a fist.
func joints(bend: Double, wrist: CGPoint = CGPoint(x: 300, y: 200), palm: Double = 60, fingers: Int = 4)
    -> HandJoints
{
    let offsets: [Double] = [-0.3, -0.1, 0.1, 0.3]
    let made = offsets.prefix(fingers).map { offset -> HandJoints.Finger in
        let knuckle = CGPoint(x: wrist.x + palm * sin(offset), y: wrist.y + palm * cos(offset))
        // The knuckle bends a little in a fist too, folding the finger towards the palm.
        let base = offset + bend * 0.6
        let middle = step(from: knuckle, angle: base, length: palm * 0.45)
        let top = step(from: middle, angle: base + bend, length: palm * 0.3)
        let tip = step(from: top, angle: base + 2 * bend, length: palm * 0.25)
        return HandJoints.Finger(knuckle: knuckle, middle: middle, top: top, tip: tip)
    }
    return HandJoints(wrist: wrist, fingers: Array(made))
}

/// A point `length` from `point`, at `angle` radians clockwise from straight up.
private func step(from point: CGPoint, angle: Double, length: Double) -> CGPoint {
    CGPoint(x: point.x + length * sin(angle), y: point.y + length * cos(angle))
}

/// The features of a drawn hand bent by `bend`, which always has enough fingers to read.
func features(bend: Double) -> HandFeatures {
    guard let features = joints(bend: bend).features else { fatalError("A drawn hand always has features") }
    return features
}

/// A reading of a hand bent by `bend`, centred at (`x`, `y`) in the image.
func hand(bend: Double, x: Double = 0.5, y: Double = 0.5, confidence: Double = 0.9) -> HandReading {
    HandReading(features: features(bend: bend), centre: CGPoint(x: x, y: y), size: 0.15, confidence: confidence)
}

enum Hands {
    static let open = 0.0
    static let fist = 1.4
    static let halfway = 0.7

    /// A calibration from the drawn open hand and fist, with a little natural variation.
    static let calibration: HandCalibration = {
        do {
            return try HandCalibration.fit(
                open: (0..<10).map { features(bend: 0.02 * Double($0 % 3)) },
                fist: (0..<10).map { features(bend: 1.4 - 0.03 * Double($0 % 3)) }
            )
        } catch {
            fatalError("The drawn open hand and fist are far apart: \(error)")
        }
    }()
}
