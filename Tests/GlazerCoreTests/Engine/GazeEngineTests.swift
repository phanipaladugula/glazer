import Testing

@testable import GlazerCore

@Suite("GazeEngine")
struct GazeEngineTests {
    /// Runs `seconds` of frames at 10 a second, the user facing `yaw`.
    func run(
        _ engine: inout GazeEngine, from start: Double, seconds: Double, yaw: Double, pitch: Double = 0
    ) -> [GazeEngine.Output] {
        stride(from: start, to: start + seconds, by: 0.1).map { time in
            engine.process(frame(at: time, face(yaw: yaw, pitch: pitch)))
        }
    }

    @Test("Turning to the monitor switches focus once")
    func switchesOnce() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        engine.setFocusedDisplay(macBookID)

        let atMacBook = run(&engine, from: 0, seconds: 1, yaw: -4, pitch: -8)
        let atMonitor = run(&engine, from: 1, seconds: 2, yaw: 28, pitch: 2)

        #expect(atMacBook.allSatisfy { $0.switchedTo == nil && $0.status == .following })
        #expect(atMonitor.compactMap(\.switchedTo) == [monitorID])
        #expect(atMonitor.last?.focusedDisplay == monitorID)
    }

    @Test("Without a calibration, the pose is reported but nothing switches")
    func uncalibrated() {
        var engine = GazeEngine(calibration: nil)
        let outputs = run(&engine, from: 0, seconds: 1, yaw: 20)

        #expect(outputs.last?.pose != nil)
        #expect(outputs.allSatisfy { $0.focusedDisplay == nil && $0.switchedTo == nil })
    }

    @Test("The user's face is reported while they're followed")
    func userFace() {
        var engine = GazeEngine(calibration: nil)
        let followed = run(&engine, from: 0, seconds: 1, yaw: 0)
        let empty = engine.process(frame(at: 1))

        #expect(followed.last?.userFace == face().bounds)
        #expect(empty.userFace == nil)
    }

    @Test("How far the user's head is from the nearest display is reported, however far")
    func facingDistance() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        let atMonitor = run(&engine, from: 0, seconds: 1, yaw: 28, pitch: 2)
        let farAway = run(&engine, from: 1, seconds: 1, yaw: 90, pitch: 0)

        #expect(atMonitor.last?.facingDistance.map { $0 < 2 } == true)
        #expect(farAway.last?.facingDistance.map { $0 > 30 } == true)
        #expect(engine.process(frame(at: 3)).facingDistance == nil)
    }

    @Test("The nearest face is the biggest")
    func nearestFace() {
        let small = face(x: 0.2, size: 0.1)
        let big = face(x: 0.7, size: 0.3)

        #expect(frame(at: 0, small, big).nearestFace == big)
        #expect(frame(at: 0).nearestFace == nil)
    }

    @Test("An empty, well-lit view is searching")
    func searching() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        #expect(engine.process(frame(at: 0)).status == .searching)
    }

    @Test("An empty, dark view is too dark")
    func tooDark() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        #expect(engine.process(frame(at: 0, brightness: 0.01)).status == .tooDark)
    }

    @Test("A user who is visible in the dark is still followed")
    func dimButVisible() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        let output = engine.process(frame(at: 0, face(), brightness: 0.01))
        #expect(output.status == .following)
        #expect(output.lightLevel == .tooDark)
    }

    @Test("With face lock, a stranger is not recognised and switches nothing")
    func stranger() {
        let verifier = IdentityVerifier(template: FaceTemplate(signatures: [People.alice]), threshold: 0.9)
        var engine = GazeEngine(calibration: twoDisplayCalibration, verifier: verifier)
        engine.setFocusedDisplay(macBookID)

        let outputs = stride(from: 0.0, to: 2, by: 0.1).map { time in
            engine.process(frame(at: time, face(yaw: 28, signature: People.bob)))
        }
        #expect(outputs.allSatisfy { $0.status == .notRecognized && $0.switchedTo == nil })
    }

    @Test("Losing the user cancels a half-finished switch")
    func lostMidSwitch() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        engine.setFocusedDisplay(macBookID)

        _ = run(&engine, from: 0, seconds: 0.3, yaw: 28, pitch: 2)
        _ = engine.process(frame(at: 1.0))
        let output = engine.process(frame(at: 1.1, face(yaw: 28, pitch: 2)))

        #expect(output.switchedTo == nil)
        #expect(output.focusedDisplay == macBookID)
    }
}

@Suite("GazeEngine settings")
struct GazeEngineSettingsTests {
    @Test("Changing the dwell keeps the user followed and applies the new delay")
    func changeDwell() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        engine.setFocusedDisplay(macBookID)
        _ = engine.process(frame(at: 0, face(yaw: -4, pitch: -8)))

        engine.setDwell(1.0)
        _ = engine.process(frame(at: 0.1, face(yaw: 28, pitch: 2)))
        let early = engine.process(frame(at: 0.8, face(yaw: 28, pitch: 2)))
        let late = engine.process(frame(at: 1.2, face(yaw: 28, pitch: 2)))

        #expect(early.status == .following && early.focusedDisplay == macBookID)
        #expect(late.focusedDisplay == monitorID)
    }
}

@Suite("GazeEngine facing")
struct GazeEngineFacingTests {
    @Test("Facing changes on the frame the head turns; focus waits for the dwell")
    func facingIsImmediate() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        engine.setFocusedDisplay(macBookID)
        _ = engine.process(frame(at: 0, face(yaw: -4, pitch: -8)))
        let turned = engine.process(frame(at: 0.1, face(yaw: 28, pitch: 2)))

        #expect(turned.facingDisplay == monitorID)
        #expect(turned.focusedDisplay == macBookID)
    }
}

@Suite("GazeEngine, passthroughs")
struct GazeEnginePassthroughTests {
    @Test("Signatures are needed only with face lock")
    func signatures() {
        let verifier = IdentityVerifier(template: FaceTemplate(signatures: [People.alice]))
        #expect(!GazeEngine(calibration: twoDisplayCalibration).needsSignatures(at: 0))
        #expect(GazeEngine(calibration: twoDisplayCalibration, verifier: verifier).needsSignatures(at: 0))
    }

    @Test("A manual move holds focus until the head turns")
    func userFocused() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        engine.setFocusedDisplay(macBookID)
        _ = engine.process(frame(at: 0, face(yaw: -4, pitch: -8)))

        engine.userFocused(monitorID)
        let later = (1...20).map { step in
            engine.process(frame(at: 0.1 * Double(step), face(yaw: -4, pitch: -8)))
        }
        #expect(later.last?.focusedDisplay == monitorID)
        #expect(later.allSatisfy { $0.switchedTo == nil })
    }

    @Test("A brief dropout keeps the last status")
    func holdingKeepsStatus() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        _ = engine.process(frame(at: 0, face()))
        #expect(engine.process(frame(at: 0.2)).status == .following)
    }

    @Test("Looking far from every display faces none of them")
    func facingNone() {
        var engine = GazeEngine(calibration: twoDisplayCalibration)
        let output = engine.process(frame(at: 0, face(yaw: -60, pitch: -8)))
        #expect(output.status == .following)
        #expect(output.facingDisplay == nil)
    }
}
