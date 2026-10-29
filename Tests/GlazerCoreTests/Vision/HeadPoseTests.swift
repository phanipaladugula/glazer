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
}
