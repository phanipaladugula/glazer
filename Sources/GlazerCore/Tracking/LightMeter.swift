import Foundation

/// How well the camera can see.
public enum LightLevel: Equatable, Sendable {
    case good
    /// Dim, but faces can still be found. Accuracy may drop.
    case dim
    /// Too dark to find a face reliably. Glazer pauses rather than guess.
    case tooDark
}

/// Turns frame brightness into a ``LightLevel``, without flickering between levels.
///
/// Brightness is averaged over about a second, and moving back to a brighter level needs
/// a little more light than moving down did.
public struct LightMeter: Sendable {
    public struct Thresholds: Sendable {
        /// Below this average brightness, the level drops to ``LightLevel/tooDark``.
        public var tooDark: Double
        /// Below this, the level drops to ``LightLevel/dim``.
        public var dim: Double
        /// How much brighter than a threshold it must get to move back up.
        public var hysteresis: Double

        public init(tooDark: Double = 0.06, dim: Double = 0.15, hysteresis: Double = 0.02) {
            self.tooDark = tooDark
            self.dim = dim
            self.hysteresis = hysteresis
        }
    }

    public let thresholds: Thresholds
    public private(set) var level: LightLevel = .good

    private var average: Double?
    private let smoothing: Double

    /// - Parameter smoothing: The weight of each new frame in the running average.
    ///   At 10 frames a second, 0.15 averages over roughly the last second.
    public init(thresholds: Thresholds = Thresholds(), smoothing: Double = 0.15) {
        self.thresholds = thresholds
        self.smoothing = smoothing
    }

    /// Adds a frame's brightness and returns the current level.
    @discardableResult
    public mutating func update(brightness: Double) -> LightLevel {
        let average = self.average.map { $0 + smoothing * (brightness - $0) } ?? brightness
        self.average = average

        let up = thresholds.hysteresis
        switch level {
        case .good:
            if average < thresholds.tooDark {
                level = .tooDark
            } else if average < thresholds.dim {
                level = .dim
            }
        case .dim:
            if average < thresholds.tooDark {
                level = .tooDark
            } else if average >= thresholds.dim + up {
                level = .good
            }
        case .tooDark:
            if average >= thresholds.dim + up {
                level = .good
            } else if average >= thresholds.tooDark + up {
                level = .dim
            }
        }
        return level
    }
}
