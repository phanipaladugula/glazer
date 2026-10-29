/// The head poses recorded while the user looked at each display: at its centre, and at
/// each of its corners.
public struct Calibration: Equatable, Sendable, Codable {
    /// Where on a display a pose was recorded.
    public enum Spot: String, CaseIterable, Sendable, Codable {
        case centre, topLeft, topRight, bottomRight, bottomLeft

        /// Where the spot is on the display, from (0, 0) at the top left to (1, 1) at the
        /// bottom right.
        public var position: (x: Double, y: Double) {
            switch self {
            case .centre: (0.5, 0.5)
            case .topLeft: (0, 0)
            case .topRight: (1, 0)
            case .bottomRight: (1, 1)
            case .bottomLeft: (0, 1)
            }
        }
    }

    public struct Point: Equatable, Sendable, Codable {
        public let displayID: Display.ID
        public let spot: Spot
        public let pose: HeadPose

        public init(displayID: Display.ID, spot: Spot = .centre, pose: HeadPose) {
            self.displayID = displayID
            self.spot = spot
            self.pose = pose
        }

        private enum CodingKeys: String, CodingKey {
            case displayID, spot, pose
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            displayID = try container.decode(Display.ID.self, forKey: .displayID)
            // Glazer 0.1 recorded only the centre of each display.
            spot = try container.decodeIfPresent(Spot.self, forKey: .spot) ?? .centre
            pose = try container.decode(HeadPose.self, forKey: .pose)
        }
    }

    public enum Issue: Equatable, Sendable {
        /// Two displays were recorded at nearly the same head pose, so Glazer can't tell
        /// them apart. Usually the user didn't turn their head, or the displays are
        /// stacked very close together.
        case tooClose(Display.ID, Display.ID)
    }

    public let points: [Point]

    public init(points: [Point]) {
        self.points = points
    }

    /// The displays calibrated, in the order they were recorded.
    public var displayIDs: [Display.ID] {
        var seen = Set<Display.ID>()
        return points.map(\.displayID).filter { seen.insert($0).inserted }
    }

    /// The pose facing the middle of the display.
    public func pose(for displayID: Display.ID) -> HeadPose? {
        let points = points.filter { $0.displayID == displayID }
        return (points.first { $0.spot == .centre } ?? points.first)?.pose
    }

    /// The poses that face the display, from its centre and corners.
    public func region(for displayID: Display.ID) -> PoseRegion? {
        let poses = points.filter { $0.displayID == displayID }.map(\.pose)
        return poses.isEmpty ? nil : PoseRegion(poses: poses)
    }

    /// Whether every display was recorded at its corners as well as its centre. Older
    /// calibrations have only centres; they work, but less well near the edges.
    public var hasCorners: Bool {
        let spots = Set(Spot.allCases)
        return displayIDs.allSatisfy { id in
            Set(points.filter { $0.displayID == id }.map(\.spot)) == spots
        }
    }

    /// Whether this calibration can be used with `displays`: each one has a point, and
    /// there are at least two to choose between.
    public func covers(_ displays: [Display]) -> Bool {
        displays.count >= 2 && displays.allSatisfy { pose(for: $0.id) != nil }
    }

    /// This calibration with only the points for `displays`, so a display that has been
    /// disconnected can never be chosen.
    public func restricted(to displays: [Display]) -> Calibration {
        let connected = Set(displays.map(\.id))
        return Calibration(points: points.filter { connected.contains($0.displayID) })
    }

    /// The first problem that would make displays hard to tell apart, if any: their
    /// centres are too close together, or one's centre lies on another's region.
    ///
    /// - Parameter minimumSeparation: The smallest distance, in degrees, that two
    ///   displays' centre poses may be apart.
    public func issue(minimumSeparation: Double = 6, weights: AxisWeights = .sideBySide) -> Issue? {
        let ids = displayIDs
        for (index, first) in ids.enumerated() {
            for second in ids[(index + 1)...] {
                guard let firstPose = pose(for: first), let secondPose = pose(for: second) else { continue }
                if firstPose.distance(to: secondPose, weights: weights) < minimumSeparation
                    || region(for: first)?.contains(secondPose, weights: weights) == true
                    || region(for: second)?.contains(firstPose, weights: weights) == true
                {
                    return .tooClose(first, second)
                }
            }
        }
        return nil
    }
}
