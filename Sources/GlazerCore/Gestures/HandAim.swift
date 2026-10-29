import CoreGraphics
import Foundation

/// Where the user holds their hand for each display, so a gesture can go to the display
/// the hand is held towards.
///
/// The camera can't see where a hand points, but it sees where the hand is relative to
/// the face: held towards a display on the left, it's further to one side than when held
/// towards the laptop below. During calibration the user holds their hand towards each
/// display in turn. Positions are measured from the face, in face heights, so
/// they still hold when the user leans or moves their chair.
///
/// When the hand is held in much the same place for every display, the positions can't
/// tell displays apart, and gestures go to the display the user faces instead.
public struct HandAim: Codable, Equatable, Sendable {
    public enum Problem: Error, Equatable, Sendable {
        /// A display had too few readings.
        case tooFewReadings
        /// Fewer than two displays.
        case tooFewDisplays
        /// The hand was held in much the same place for these two displays.
        case tooClose(Display.ID, Display.ID)
    }

    public struct Target: Codable, Equatable, Sendable {
        public let display: Display.ID
        /// The typical hand position for this display, relative to the face.
        public let offset: CGPoint

        public init(display: Display.ID, offset: CGPoint) {
            self.display = display
            self.offset = offset
        }
    }

    public let targets: [Target]
    /// How much the hand's position varies when held towards the same display, in face
    /// units.
    public let variation: Double

    public init(targets: [Target], variation: Double) {
        self.targets = targets
        self.variation = variation
    }

    public static let minimumReadings = 6
    /// How far apart, in typical variations, every two displays' positions must be.
    public static let minimumSeparation = 4.0
    /// The least variation assumed: a few steady frames can vary almost not at all.
    static let minimumVariation = 0.12

    /// Fits targets to hand positions recorded for each display.
    public static func fit(_ readings: [Display.ID: [CGPoint]]) throws(Problem) -> HandAim {
        guard readings.count >= 2 else { throw .tooFewDisplays }
        guard readings.values.allSatisfy({ $0.count >= minimumReadings }) else { throw .tooFewReadings }

        let targets = readings.keys.sorted().map { display in
            let points = readings[display] ?? []
            return Target(
                display: display,
                offset: CGPoint(
                    x: Statistics.median(points.map { Double($0.x) }),
                    y: Statistics.median(points.map { Double($0.y) })))
        }
        let deviations = readings.values.flatMap { points in
            [Statistics.deviation(points.map { Double($0.x) }), Statistics.deviation(points.map { Double($0.y) })]
        }
        let variation = max(deviations.max() ?? 0, minimumVariation)

        for (index, first) in targets.enumerated() {
            for second in targets[(index + 1)...]
            where first.offset.distance(to: second.offset) < minimumSeparation * variation {
                throw .tooClose(first.display, second.display)
            }
        }
        return HandAim(targets: targets, variation: variation)
    }

    /// The display a hand at `offset` from the face is held towards, or `nil` when it's
    /// not clearly nearer one display's position than every other, or far from all of them.
    public func display(for offset: CGPoint) -> Display.ID? {
        let ranked =
            targets
            .map { ($0.display, $0.offset.distance(to: offset)) }
            .sorted { $0.1 < $1.1 }
        guard let best = ranked.first, best.1 <= 3 * variation else { return nil }
        if ranked.count > 1, best.1 > 0.6 * ranked[1].1 { return nil }
        return best.0
    }

    /// Whether this covers every one of `displays`.
    public func covers(_ displays: [Display]) -> Bool {
        let aimed = Set(targets.map(\.display))
        return displays.allSatisfy { aimed.contains($0.id) }
    }
}
