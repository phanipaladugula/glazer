import Testing

@testable import GlazerCore

@Suite("CalibrationRecorder")
struct CalibrationRecorderTests {
    /// Feeds `poses` at 10 frames a second, starting at `start`.
    func record(
        _ recorder: inout CalibrationRecorder, _ poses: [HeadPose], start: Double = 0
    ) -> CalibrationRecorder.Progress {
        var progress = recorder.progress
        for (index, pose) in poses.enumerated() {
            progress = recorder.add(pose, at: start + Double(index) * 0.1)
        }
        return progress
    }

    @Test("The first moments are for settling")
    func settles() {
        var recorder = CalibrationRecorder()
        #expect(recorder.add(HeadPose(yaw: 20, pitch: 0), at: 0) == .settling)
        #expect(recorder.add(HeadPose(yaw: 20, pitch: 0), at: 0.5) == .settling)
    }

    @Test("A steady look finishes with the median pose")
    func steadyLook() {
        var recorder = CalibrationRecorder()
        let poses = (0..<30).map { HeadPose(yaw: 28 + Double($0 % 3) - 1, pitch: 2) }

        #expect(record(&recorder, poses) == .finished(HeadPose(yaw: 28, pitch: 2)))
    }

    @Test("A single bad frame doesn't spoil the result")
    func outlier() {
        var recorder = CalibrationRecorder()
        var poses = Array(repeating: HeadPose(yaw: 28, pitch: 2), count: 30)
        poses[15] = HeadPose(yaw: -40, pitch: 30)

        #expect(record(&recorder, poses) == .finished(HeadPose(yaw: 28, pitch: 2)))
    }

    @Test("A moving head restarts the recording")
    func unsteady() {
        var recorder = CalibrationRecorder()
        let progress = (0..<30).map { step in
            recorder.add(HeadPose(yaw: Double(step) * 2, pitch: 0), at: Double(step) * 0.1)
        }

        #expect(progress.contains(.unsteady))
        #expect(!progress.contains { if case .finished = $0 { true } else { false } })
    }

    @Test("Progress rises while recording")
    func progress() {
        var recorder = CalibrationRecorder()
        let poses = Array(repeating: HeadPose(yaw: 0, pitch: 0), count: 17)
        guard case .recording(let fraction) = record(&recorder, poses) else {
            Issue.record("Expected to be recording")
            return
        }
        #expect(fraction > 0.5 && fraction < 1)
    }
}
