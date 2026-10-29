import Foundation
import Testing

@testable import GlazerCore

private func pose(_ yaw: Double, _ pitch: Double) -> HeadPose {
    HeadPose(yaw: yaw, pitch: pitch)
}

private let even = AxisWeights(yaw: 1, pitch: 1)

@Suite("Pose region")
struct PoseRegionTests {
    /// A display's centre and corners: 20° wide and 10° tall.
    let region = PoseRegion(poses: [pose(0, 0), pose(-10, 5), pose(10, 5), pose(10, -5), pose(-10, -5)])

    @Test("The hull keeps the corners and drops the centre inside them")
    func hull() {
        #expect(region.vertices.count == 4)
        #expect(!region.vertices.contains(pose(0, 0)))
    }

    @Test("Repeated and collinear poses are dropped")
    func degenerate() {
        #expect(PoseRegion.hull(of: [pose(1, 1), pose(1, 1)]) == [pose(1, 1)])
        #expect(PoseRegion.hull(of: [pose(0, 0), pose(5, 0), pose(10, 0)]) == [pose(0, 0), pose(10, 0)])
        #expect(PoseRegion.hull(of: [pose(0, 0), pose(5, 0), pose(10, 0), pose(5, 5)]).count == 3)
    }

    @Test("A pose on the region is at distance 0, its edges and corners included")
    func inside() {
        for inside in [pose(0, 0), pose(9, 4), pose(-10, 0), pose(10, -5)] {
            #expect(region.distance(to: inside, weights: even) == 0)
            #expect(region.contains(inside, weights: even))
        }
    }

    @Test("Outside, the distance is to the nearest edge or corner")
    func outside() {
        #expect(region.distance(to: pose(14, 0), weights: even) == 4)
        #expect(region.distance(to: pose(0, -8), weights: even) == 3)
        #expect(abs(region.distance(to: pose(13, 9), weights: even) - 5) < 1e-9)
    }

    @Test("Weights scale each axis")
    func weighted() {
        let weights = AxisWeights(yaw: 1, pitch: 0.5)
        #expect(region.distance(to: pose(0, -9), weights: weights) == 2)
        #expect(region.distance(to: pose(12, 0), weights: weights) == 2)
    }

    @Test("A region from one pose is that pose; from two, the line between them")
    func pointAndLine() {
        let point = PoseRegion(poses: [pose(3, 4)])
        #expect(point.distance(to: pose(0, 0), weights: even) == 5)
        #expect(!point.contains(pose(0, 0), weights: even))

        let line = PoseRegion(poses: [pose(0, 0), pose(10, 0)])
        #expect(line.distance(to: pose(5, 3), weights: even) == 3)
        #expect(line.distance(to: pose(13, 4), weights: even) == 5)
    }

    @Test("An empty region is infinitely far")
    func empty() {
        #expect(PoseRegion(poses: []).distance(to: pose(0, 0), weights: even) == .infinity)
    }
}

/// The poses at the centre and corners of a display, `width` by `height` degrees.
private func points(_ id: Display.ID, centre: HeadPose, width: Double, height: Double) -> [Calibration.Point] {
    Calibration.Spot.allCases.map { spot in
        let (x, y) = spot.position
        let pose = HeadPose(yaw: centre.yaw + (x - 0.5) * width, pitch: centre.pitch + (0.5 - y) * height)
        return Calibration.Point(displayID: id, spot: spot, pose: pose)
    }
}

@Suite("Calibration with corners")
struct CornerCalibrationTests {
    /// A wide MacBook straight ahead and below, and a narrow monitor close on its right.
    let calibration = Calibration(
        points: points(1, centre: pose(0, -15), width: 50, height: 14)
            + points(2, centre: pose(40, -5), width: 16, height: 10))

    @Test("Centre poses, displays and corners are read back")
    func readBack() {
        #expect(calibration.displayIDs == [1, 2])
        #expect(calibration.pose(for: 1) == pose(0, -15))
        #expect(calibration.pose(for: 2) == pose(40, -5))
        #expect(calibration.region(for: 1)?.vertices.count == 4)
        #expect(calibration.region(for: 3) == nil)
        #expect(calibration.hasCorners)
        #expect(!twoDisplayCalibration.hasCorners)
    }

    @Test("Near a wide display's edge, its region wins where its centre would lose")
    func edgeOfWideDisplay() {
        let nearEdge = pose(24, -10)
        let weights = AxisWeights.sideBySide

        // Measured to the centres alone, the monitor is nearer.
        let centresOnly = Calibration(points: [
            .init(displayID: 1, pose: pose(0, -15)), .init(displayID: 2, pose: pose(40, -5)),
        ])
        var byCentre = DisplayClassifier(calibration: centresOnly)
        byCentre.configuration.weights = weights
        byCentre.update(with: nearEdge, at: 0)
        #expect(byCentre.nearest == 2)

        // With the corners, Glazer knows the MacBook reaches that far.
        var byRegion = DisplayClassifier(calibration: calibration)
        byRegion.configuration.weights = weights
        byRegion.update(with: nearEdge, at: 0)
        #expect(byRegion.nearest == 1)
    }

    @Test("Turning past a display's edge onto the next switches after the dwell")
    func switchesAcrossTheEdge() {
        var classifier = DisplayClassifier(calibration: calibration)
        classifier.setFocused(1)
        for time in stride(from: 0.0, through: 1, by: 0.1) {
            classifier.update(with: pose(36, -4), at: time)
        }
        #expect(classifier.focused == 2)
    }

    @Test("Where two regions overlap, focus stays where it is")
    func overlapKeepsFocus() {
        let overlapping = Calibration(
            points: points(1, centre: pose(0, 0), width: 30, height: 10)
                + points(2, centre: pose(26, 0), width: 30, height: 10))
        var classifier = DisplayClassifier(calibration: overlapping)
        classifier.setFocused(1)
        for time in stride(from: 0.0, through: 2, by: 0.1) {
            classifier.update(with: pose(14, 0), at: time)
        }
        #expect(classifier.focused == 1)
        // Both regions contain the pose; the nearer centre decides which is "nearest".
        #expect(classifier.nearest == 2)
    }

    @Test("A display whose centre lies on another's region is flagged")
    func centreOnAnotherRegion() {
        let swallowed = Calibration(
            points: points(1, centre: pose(0, 0), width: 40, height: 20)
                + [.init(displayID: 2, pose: pose(15, 0))])
        #expect(swallowed.issue() == .tooClose(1, 2))
        #expect(calibration.issue(weights: .sideBySide) == nil)
    }

    @Test("A calibration from Glazer 0.1, without spots, loads as centres")
    func decodesOlderCalibration() throws {
        let data = try JSONEncoder().encode(calibration)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stripped = try #require(object["points"] as? [[String: Any]]).map {
            $0.filter { $0.key != "spot" }
        }
        object["points"] = stripped
        let older = try JSONDecoder().decode(
            Calibration.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(older.points.allSatisfy { $0.spot == .centre })
        #expect(older.points.map(\.pose) == calibration.points.map(\.pose))
    }

    @Test("Spots survive a round trip")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(Calibration.self, from: JSONEncoder().encode(calibration))
        #expect(decoded == calibration)
    }
}
