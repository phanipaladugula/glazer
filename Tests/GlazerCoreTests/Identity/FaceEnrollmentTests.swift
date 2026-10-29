import Testing

@testable import GlazerCore

@Suite("FaceEnrollment")
struct FaceEnrollmentTests {
    /// A frame of Alice facing `yaw`, sampled at `time`.
    func alice(yaw: Double, at time: Double) -> Frame {
        frame(at: time, face(size: 0.4, yaw: yaw, signature: People.aliceAgain))
    }

    @Test("Turning slowly across every range completes enrolment")
    func completes() {
        var enrollment = FaceEnrollment()
        var time = 0.0
        for yaw in [-20.0, 0, 20] {
            for _ in 0..<4 {
                enrollment.add(alice(yaw: yaw, at: time))
                time += 0.2
            }
        }
        #expect(enrollment.feedback == .done)
        #expect(enrollment.template?.signatures.count == 12)
        #expect(enrollment.progress == 1)
    }

    @Test("Looking straight ahead only fills the centre")
    func needsTurns() {
        var enrollment = FaceEnrollment()
        for step in 0..<10 {
            enrollment.add(alice(yaw: 0, at: Double(step) * 0.2))
        }
        #expect(enrollment.feedback == .turnSlowly)
        #expect(enrollment.rangeProgress == [0, 1, 0])
        #expect(enrollment.template == nil)
    }

    @Test("Two people in view pauses enrolment")
    func onePerson() {
        var enrollment = FaceEnrollment()
        let both = frame(at: 0, face(x: 0.3, signature: People.alice), face(x: 0.7, signature: People.bob))
        #expect(enrollment.add(both) == .onlyOnePerson)
        #expect(enrollment.progress == 0)
    }

    @Test("A different person partway through restarts enrolment")
    func restartsOnSwap() {
        var enrollment = FaceEnrollment()
        enrollment.add(alice(yaw: 0, at: 0))
        let bob = frame(at: 0.2, face(size: 0.4, signature: People.bob))
        #expect(enrollment.add(bob) == .restarted)
        #expect(enrollment.progress == 0)
    }

    @Test("A distant face is asked to move closer")
    func moveCloser() {
        var enrollment = FaceEnrollment()
        let distant = frame(at: 0, face(size: 0.12, signature: People.alice))
        #expect(enrollment.add(distant) == .moveCloser)
    }

    @Test("Samples closer together than the interval are skipped")
    func interval() {
        var enrollment = FaceEnrollment()
        enrollment.add(alice(yaw: 0, at: 0))
        enrollment.add(alice(yaw: 0, at: 0.05))
        #expect(enrollment.rangeProgress[1] == 0.25)
    }

    @Test("A turned face is compared with the closest sample, not the first")
    func comparesWithClosest() {
        var configuration = FaceEnrollment.Configuration()
        configuration.minimumConsistency = 0.9
        var enrollment = FaceEnrollment(configuration: configuration)
        let straight = FaceSignature(values: [1, 0, 0])
        let slightlyTurned = FaceSignature(values: [0.95, 0.31, 0])
        let turned = FaceSignature(values: [0.81, 0.59, 0])

        enrollment.add(frame(at: 0, face(size: 0.4, yaw: 0, signature: straight)))
        enrollment.add(frame(at: 0.2, face(size: 0.4, yaw: 10, signature: slightlyTurned)))
        // Only about 0.81 like the first sample, but about 0.96 like the second.
        #expect(enrollment.add(frame(at: 0.4, face(size: 0.4, yaw: 20, signature: turned))) != .restarted)
    }
}
