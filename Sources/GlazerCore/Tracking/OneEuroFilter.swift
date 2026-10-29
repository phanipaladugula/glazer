import Foundation

/// Smooths a noisy signal while keeping fast movements responsive.
///
/// The One Euro filter (Casiez, Roussel and Vogel, CHI 2012) is a low-pass filter whose
/// cutoff rises with the signal's speed: a still head gives a steady angle, and a quick
/// turn comes through without lag.
public struct OneEuroFilter: Sendable {
    /// The cutoff frequency, in hertz, when the signal is still. Lower is smoother.
    public var minimumCutoff: Double
    /// How much the cutoff rises with speed. Higher reacts faster to quick turns.
    public var speedCoefficient: Double
    /// The cutoff used to smooth the speed estimate itself.
    public var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTimestamp: TimeInterval?

    public init(minimumCutoff: Double = 1.0, speedCoefficient: Double = 0.02, derivativeCutoff: Double = 1.0) {
        self.minimumCutoff = minimumCutoff
        self.speedCoefficient = speedCoefficient
        self.derivativeCutoff = derivativeCutoff
    }

    /// Adds a sample and returns the smoothed value.
    public mutating func filter(_ value: Double, at timestamp: TimeInterval) -> Double {
        guard let previousValue, let previousTimestamp, timestamp > previousTimestamp else {
            self.previousValue = value
            self.previousTimestamp = timestamp
            return value
        }

        let elapsed = timestamp - previousTimestamp
        let derivative = (value - previousValue) / elapsed
        let smoothedDerivative = Self.blend(
            derivative, previousDerivative, alpha: Self.alpha(cutoff: derivativeCutoff, elapsed: elapsed))

        let cutoff = minimumCutoff + speedCoefficient * abs(smoothedDerivative)
        let smoothed = Self.blend(value, previousValue, alpha: Self.alpha(cutoff: cutoff, elapsed: elapsed))

        self.previousValue = smoothed
        self.previousDerivative = smoothedDerivative
        self.previousTimestamp = timestamp
        return smoothed
    }

    /// Forgets the history, so the next sample is taken as is.
    public mutating func reset() {
        previousValue = nil
        previousDerivative = 0
        previousTimestamp = nil
    }

    private static func alpha(cutoff: Double, elapsed: TimeInterval) -> Double {
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + timeConstant / elapsed)
    }

    private static func blend(_ value: Double, _ previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}

/// A ``OneEuroFilter`` for each angle of a ``HeadPose``.
public struct HeadPoseFilter: Sendable {
    private var yaw: OneEuroFilter
    private var pitch: OneEuroFilter

    public init(minimumCutoff: Double = 1.0, speedCoefficient: Double = 0.02) {
        yaw = OneEuroFilter(minimumCutoff: minimumCutoff, speedCoefficient: speedCoefficient)
        pitch = OneEuroFilter(minimumCutoff: minimumCutoff, speedCoefficient: speedCoefficient)
    }

    public mutating func filter(_ pose: HeadPose, at timestamp: TimeInterval) -> HeadPose {
        HeadPose(
            yaw: yaw.filter(pose.yaw, at: timestamp),
            pitch: pitch.filter(pose.pitch, at: timestamp)
        )
    }

    public mutating func reset() {
        yaw.reset()
        pitch.reset()
    }
}
