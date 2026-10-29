/// The head pose recorded while the user looked at each display.
public struct Calibration: Equatable, Sendable, Codable {
    public struct Point: Equatable, Sendable, Codable {
        public let displayID: Display.ID
        public let pose: HeadPose

        public init(displayID: Display.ID, pose: HeadPose) {
            self.displayID = displayID
            self.pose = pose
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

    public func pose(for displayID: Display.ID) -> HeadPose? {
        points.first { $0.displayID == displayID }?.pose
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

    /// The first problem that would make displays hard to tell apart, if any.
    ///
    /// - Parameter minimumSeparation: The smallest distance, in degrees, that two
    ///   displays' poses may be apart.
    public func issue(minimumSeparation: Double = 6, pitchWeight: Double = 0.6) -> Issue? {
        for (index, first) in points.enumerated() {
            for second in points[(index + 1)...]
            where first.pose.distance(to: second.pose, pitchWeight: pitchWeight) < minimumSeparation {
                return .tooClose(first.displayID, second.displayID)
            }
        }
        return nil
    }
}
