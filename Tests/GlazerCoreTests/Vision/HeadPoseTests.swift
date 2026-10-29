import Testing

@testable import GlazerCore

@Suite("HeadPose")
struct HeadPoseTests {
    @Test("Distance combines yaw and weighted pitch")
    func distance() {
        let a = HeadPose(yaw: 0, pitch: 0)
        let b = HeadPose(yaw: 3, pitch: 8)
        #expect(a.distance(to: b) == (9.0 + 64.0).squareRoot())
        #expect(a.distance(to: b, pitchWeight: 0.5) == 5)
    }

    @Test("Weighted distance scales each axis")
    func weightedDistance() {
        let a = HeadPose(yaw: 0, pitch: 0)
        let b = HeadPose(yaw: 6, pitch: 4)
        #expect(a.distance(to: b, weights: AxisWeights(yaw: 0.5, pitch: 1)) == 5)
    }
}
