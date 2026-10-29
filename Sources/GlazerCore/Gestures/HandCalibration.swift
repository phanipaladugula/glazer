import Foundation

/// What the user's own open hand and fist look like to the camera.
///
/// Hands, cameras and the angle a hand is held at differ a lot, so fixed thresholds
/// either miss fists or see them everywhere. Instead, the user shows Glazer an open hand
/// and a fist, and every later reading is placed on the line between the two: see
/// ``openness(of:)``.
public struct HandCalibration: Codable, Equatable, Sendable {
    public enum Problem: Error, Equatable, Sendable {
        /// Too few readings of the open hand or the fist.
        case tooFewReadings
        /// The open hand and the fist looked too alike to tell apart reliably, such as in
        /// poor light or with the hand too far away.
        case tooSimilar
    }

    /// The typical open hand.
    public let open: HandFeatures
    /// The typical fist.
    public let fist: HandFeatures
    /// How much readings of the same shape vary, for each feature. Features that vary
    /// less count for more.
    public let variation: HandFeatures

    public init(open: HandFeatures, fist: HandFeatures, variation: HandFeatures) {
        self.open = open
        self.fist = fist
        self.variation = variation
    }

    /// The fewest readings of each shape a calibration needs.
    public static let minimumReadings = 8

    /// How far apart, in typical variations, the open hand and the fist must be. At 4,
    /// a reading must be off by two typical variations to land halfway, where neither
    /// shape counts.
    public static let minimumSeparation = 4.0

    /// The least variation assumed for each feature: a few steady frames can vary almost
    /// not at all, which would make the feature count for far too much.
    static let minimumVariation = HandFeatures(reach: 0.06, curl: 0.04, spread: 0.05)

    /// A typical adult hand about 70 cm from a laptop camera, for tools that run before
    /// the user has calibrated.
    public static let typical = HandCalibration(
        open: HandFeatures(reach: 1.9, curl: 0.12, spread: 1.4),
        fist: HandFeatures(reach: 1.05, curl: 0.85, spread: 0.7),
        variation: HandFeatures(reach: 0.15, curl: 0.12, spread: 0.12)
    )

    /// Fits a calibration to readings of the user's open hand and fist.
    public static func fit(open: [HandFeatures], fist: [HandFeatures]) throws(Problem) -> HandCalibration {
        guard open.count >= minimumReadings, fist.count >= minimumReadings else { throw .tooFewReadings }

        let openCentre = centre(of: open)
        let fistCentre = centre(of: fist)
        let floor = minimumVariation.values
        // The larger of the two shapes' variations, so neither is trusted more than it
        // deserves.
        let variation = (0..<floor.count).map { index in
            max(
                Statistics.deviation(open.map { $0.values[index] }),
                Statistics.deviation(fist.map { $0.values[index] }),
                floor[index])
        }

        let calibration = HandCalibration(
            open: openCentre, fist: fistCentre, variation: HandFeatures(values: variation))
        guard calibration.separation >= minimumSeparation else { throw .tooSimilar }
        return calibration
    }

    /// How far apart the open hand and the fist are, in typical variations.
    public var separation: Double {
        let open = self.open.values
        let fist = self.fist.values
        let variation = self.variation.values
        return (0..<open.count)
            .map { pow((open[$0] - fist[$0]) / variation[$0], 2) }
            .reduce(0, +)
            .squareRoot()
    }

    /// How open `features` is: 0 for this user's fist, 1 for their open hand, and in
    /// between for anything else.
    ///
    /// It's the reading's position along the line from fist to open hand, with each
    /// feature scaled by how much it varies, so a steady feature counts for more than a
    /// noisy one.
    public func openness(of features: HandFeatures) -> Double {
        let reading = features.values
        let open = self.open.values
        let fist = self.fist.values
        let variation = self.variation.values

        var along = 0.0
        var length = 0.0
        for index in reading.indices {
            let weight = 1 / (variation[index] * variation[index])
            let axis = open[index] - fist[index]
            along += weight * (reading[index] - fist[index]) * axis
            length += weight * axis * axis
        }
        guard length > 0 else { return 0.5 }
        return min(max(along / length, 0), 1)
    }

    private static func centre(of readings: [HandFeatures]) -> HandFeatures {
        HandFeatures(
            reach: Statistics.median(readings.map(\.reach)),
            curl: Statistics.median(readings.map(\.curl)),
            spread: Statistics.median(readings.map(\.spread))
        )
    }
}
