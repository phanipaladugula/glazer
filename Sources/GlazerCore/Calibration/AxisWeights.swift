import CoreGraphics

/// How much a degree of head turn (yaw) and a degree of head tilt (pitch) count when
/// comparing head poses.
///
/// The axis the displays are arranged along is the axis the head moves along between them,
/// so it's the one that tells them apart. The other axis mostly carries noise: Vision's
/// estimate wobbling, or the user shifting in their chair, which changes the angle the
/// camera sees without changing which display they face. Weighting by the arrangement
/// keeps that noise from deciding the display.
public struct AxisWeights: Equatable, Sendable, Codable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }

    /// Displays side by side: turning the head tells them apart, and pitch is noisier.
    public static let sideBySide = AxisWeights(yaw: 1, pitch: 0.6)

    /// Weights for `displays` as they're arranged.
    ///
    /// Each axis counts in proportion to how far the displays' centres spread along it, so
    /// displays side by side weight yaw, stacked displays weight pitch, and displays on a
    /// diagonal weight both.
    ///
    /// - Parameter floor: The least either axis counts, so neither is ever ignored.
    public init(arranging displays: [Display], floor: Double = 0.5) {
        let centres = displays.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
        guard let first = centres.first else {
            self = .sideBySide
            return
        }
        let xs = centres.map(\.x), ys = centres.map(\.y)
        let spreadX = Double((xs.max() ?? first.x) - (xs.min() ?? first.x))
        let spreadY = Double((ys.max() ?? first.y) - (ys.min() ?? first.y))
        let largest = max(spreadX, spreadY)
        guard largest > 0 else {
            self = .sideBySide
            return
        }
        self.init(yaw: max(spreadX / largest, floor), pitch: max(spreadY / largest, floor))
    }
}

extension HeadPose {
    /// The weighted angular distance to `other`, in degrees.
    public func distance(to other: HeadPose, weights: AxisWeights) -> Double {
        let yaw = (self.yaw - other.yaw) * weights.yaw
        let pitch = (self.pitch - other.pitch) * weights.pitch
        return (yaw * yaw + pitch * pitch).squareRoot()
    }
}
