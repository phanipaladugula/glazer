/// The direction a head is facing, in degrees.
///
/// Yaw is the turn left and right, and pitch the tilt up and down. Signs follow the
/// camera's convention and don't matter to Glazer: calibration records whatever the
/// camera reports for each display, and classification only compares poses.
public struct HeadPose: Equatable, Sendable, Codable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }

    /// The angular distance to `other`, in degrees.
    ///
    /// - Parameter pitchWeight: How much a degree of pitch counts relative to a degree of
    ///   yaw. Displays usually sit side by side, and pitch estimates are noisier, so
    ///   Glazer weights pitch below yaw.
    public func distance(to other: HeadPose, pitchWeight: Double = 1) -> Double {
        let yaw = self.yaw - other.yaw
        let pitch = (self.pitch - other.pitch) * pitchWeight
        return (yaw * yaw + pitch * pitch).squareRoot()
    }
}
