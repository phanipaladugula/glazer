import CoreGraphics
import Foundation

@testable import GlazerCore

/// A face centred at (`x`, `y`) with sides of `size`, in normalised image coordinates.
func face(
    x: Double = 0.5,
    y: Double = 0.5,
    size: Double = 0.3,
    yaw: Double = 0,
    pitch: Double = 0,
    confidence: Double = 0.95,
    signature: FaceSignature? = nil
) -> DetectedFace {
    DetectedFace(
        bounds: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size),
        pose: HeadPose(yaw: yaw, pitch: pitch),
        confidence: confidence,
        signature: signature
    )
}

func frame(at timestamp: TimeInterval, _ faces: DetectedFace..., brightness: Double = 0.5) -> Frame {
    Frame(timestamp: timestamp, faces: faces, brightness: brightness)
}

/// Two clearly different people, and a slight variation of the first.
enum People {
    static let alice = FaceSignature(values: [1, 0.2, 0, 0.1])
    static let aliceAgain = FaceSignature(values: [0.95, 0.25, 0.05, 0.1])
    static let bob = FaceSignature(values: [0, 0.1, 1, 0.3])
}
