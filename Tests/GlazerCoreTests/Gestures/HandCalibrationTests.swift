import CoreGraphics
import Foundation
import Testing

@testable import GlazerCore

@Suite("Hand features")
struct HandFeaturesTests {
    @Test("An open hand reaches far, with straight fingers")
    func openHand() throws {
        let features = try #require(joints(bend: Hands.open).features)

        #expect(features.reach > 1.8)
        #expect(features.curl < 0.05)
    }

    @Test("A fist reaches little, with curled fingers")
    func fist() throws {
        let features = try #require(joints(bend: Hands.fist).features)

        #expect(features.reach < 1.3)
        #expect(features.curl > 0.8)
    }

    @Test("Features don't depend on how far away the hand is")
    func scaleFree() throws {
        let near = try #require(joints(bend: 0.5, palm: 120).features)
        let far = try #require(joints(bend: 0.5, wrist: CGPoint(x: 40, y: 400), palm: 30).features)

        #expect(abs(near.reach - far.reach) < 0.001)
        #expect(abs(near.curl - far.curl) < 0.001)
        #expect(abs(near.spread - far.spread) < 0.001)
    }

    @Test("Too few fingers give no reading")
    func tooFewFingers() {
        #expect(joints(bend: 0, fingers: 2).features == nil)
        #expect(joints(bend: 0, fingers: 3).features != nil)
    }

    @Test("A hand with no size gives no reading")
    func noSize() {
        #expect(joints(bend: 0, palm: 0).features == nil)
    }

    @Test("A joint bends by the angle between its two segments")
    func bend() {
        let origin = CGPoint.zero
        #expect(HandJoints.bend(CGPoint(x: 0, y: -1), origin, CGPoint(x: 0, y: 1)) == 0)
        #expect(abs(HandJoints.bend(CGPoint(x: 0, y: -1), origin, CGPoint(x: 1, y: 0)) - .pi / 2) < 1e-9)
        #expect(HandJoints.bend(origin, origin, CGPoint(x: 1, y: 0)) == 0)
    }
}

@Suite("Hand calibration")
struct HandCalibrationTests {
    @Test("The open hand reads 1 and the fist 0")
    func ends() throws {
        let calibration = Hands.calibration
        let open = try #require(joints(bend: Hands.open).features)
        let fist = try #require(joints(bend: Hands.fist).features)

        #expect(calibration.openness(of: open) > 0.95)
        #expect(calibration.openness(of: fist) < 0.05)
    }

    @Test("Openness falls as the hand closes")
    func monotonic() throws {
        let calibration = Hands.calibration
        let readings = try stride(from: 0.0, through: 1.4, by: 0.2).map {
            calibration.openness(of: try #require(joints(bend: $0).features))
        }

        #expect(zip(readings, readings.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test("Readings beyond either end are clamped")
    func clamped() {
        let calibration = Hands.calibration
        let beyondOpen = HandFeatures(reach: 3, curl: -0.5, spread: 3)
        let beyondFist = HandFeatures(reach: 0, curl: 2, spread: 0)

        #expect(calibration.openness(of: beyondOpen) == 1)
        #expect(calibration.openness(of: beyondFist) == 0)
    }

    @Test("A calibration with identical ends reads halfway")
    func degenerate() {
        let same = HandFeatures(reach: 1, curl: 0.5, spread: 1)
        let calibration = HandCalibration(open: same, fist: same, variation: same)

        #expect(calibration.openness(of: same) == 0.5)
        #expect(calibration.separation == 0)
    }

    @Test("Too few readings can't be fitted")
    func tooFew() {
        let open = [HandFeatures](repeating: joints(bend: 0).features!, count: 3)
        let fist = [HandFeatures](repeating: joints(bend: 1.4).features!, count: 20)

        #expect(throws: HandCalibration.Problem.tooFewReadings) {
            try HandCalibration.fit(open: open, fist: fist)
        }
    }

    @Test("An open hand and fist that look alike are refused")
    func tooSimilar() {
        let open = (0..<10).map { joints(bend: 0.6 + 0.1 * Double($0 % 3)).features! }
        let fist = (0..<10).map { joints(bend: 0.7 + 0.1 * Double($0 % 3)).features! }

        #expect(throws: HandCalibration.Problem.tooSimilar) {
            try HandCalibration.fit(open: open, fist: fist)
        }
    }

    @Test("Steady readings don't make a feature count for everything")
    func variationFloor() throws {
        let calibration = try HandCalibration.fit(
            open: Array(repeating: joints(bend: 0).features!, count: 10),
            fist: Array(repeating: joints(bend: 1.4).features!, count: 10))

        #expect(calibration.variation == HandCalibration.minimumVariation)
    }

    @Test("The typical calibration tells the drawn hands apart")
    func typical() throws {
        let typical = HandCalibration.typical

        #expect(typical.separation >= HandCalibration.minimumSeparation)
        #expect(typical.openness(of: try #require(joints(bend: Hands.open).features)) > 0.7)
        #expect(typical.openness(of: try #require(joints(bend: Hands.fist).features)) < 0.3)
    }

    @Test("A calibration survives saving")
    func codable() throws {
        let data = try JSONEncoder().encode(Hands.calibration)

        #expect(try JSONDecoder().decode(HandCalibration.self, from: data) == Hands.calibration)
    }
}

@Suite("Hand calibration recorder")
struct HandCalibrationRecorderTests {
    /// Feeds `shape` at 12 frames a second from `start` for `duration` seconds, and
    /// returns the time after the last frame.
    @discardableResult
    func feed(
        _ recorder: inout HandCalibrationRecorder, bend: Double?, from start: Double, for duration: Double
    ) -> Double {
        var time = start
        while time < start + duration {
            recorder.add(bend.map { hand(bend: $0) }, at: time)
            time += 1.0 / 12
        }
        return time
    }

    @Test("It asks for an open hand first")
    func startsOpen() {
        #expect(HandCalibrationRecorder().progress == .waiting(.open))
    }

    @Test("Shapes shown in turn give a calibration")
    func records() throws {
        var recorder = HandCalibrationRecorder()
        var time = 0.0
        for bend in [Hands.open, Hands.fist, Hands.open, Hands.fist] {
            time = feed(&recorder, bend: bend, from: time, for: 2.2)
            // The hand goes down between shapes.
            time = feed(&recorder, bend: nil, from: time, for: 0.5)
        }

        guard case .finished(let calibration) = recorder.progress else {
            Issue.record("Expected a calibration, got \(recorder.progress)")
            return
        }
        #expect(calibration.openness(of: joints(bend: Hands.open).features!) > 0.9)
        #expect(recorder.fractionDone == 1)
    }

    @Test("It waits while no hand is in view")
    func waits() {
        var recorder = HandCalibrationRecorder()
        feed(&recorder, bend: nil, from: 0, for: 5)

        #expect(recorder.progress == .waiting(.open))
        #expect(recorder.fractionDone == 0)
    }

    @Test("It records once the hand has settled")
    func settles() {
        var recorder = HandCalibrationRecorder()
        feed(&recorder, bend: Hands.open, from: 0, for: 0.5)
        #expect(recorder.progress == .waiting(.open))

        feed(&recorder, bend: Hands.open, from: 0.5, for: 0.6)
        guard case .recording(.open, let fraction) = recorder.progress else {
            Issue.record("Expected recording, got \(recorder.progress)")
            return
        }
        #expect(fraction > 0 && fraction < 1)
        #expect(recorder.fractionDone > 0 && recorder.fractionDone < 0.25)
    }

    @Test("A hand that leaves while recording starts that shape again")
    func restartsWhenLost() {
        var recorder = HandCalibrationRecorder()
        let time = feed(&recorder, bend: Hands.open, from: 0, for: 1.2)
        feed(&recorder, bend: nil, from: time, for: 0.6)

        #expect(recorder.progress == .waiting(.open))
        #expect(recorder.step == 0)
    }

    @Test("A brief gap is ignored")
    func briefGap() {
        var recorder = HandCalibrationRecorder()
        var time = feed(&recorder, bend: Hands.open, from: 0, for: 1.2)
        time = feed(&recorder, bend: nil, from: time, for: 0.2)
        feed(&recorder, bend: Hands.open, from: time, for: 0.1)

        guard case .recording(.open, _) = recorder.progress else {
            Issue.record("Expected recording, got \(recorder.progress)")
            return
        }
    }

    @Test("The same shape every time fails as too similar")
    func sameShape() {
        var recorder = HandCalibrationRecorder()
        var time = 0.0
        for _ in 0..<4 {
            time = feed(&recorder, bend: Hands.halfway, from: time, for: 2.2)
            time = feed(&recorder, bend: nil, from: time, for: 0.5)
        }

        #expect(recorder.progress == .failed(.tooSimilar))
        #expect(recorder.fractionDone == 1)
        // Further readings change nothing.
        #expect(recorder.add(hand(bend: 0), at: time) == .failed(.tooSimilar))
    }

    @Test("No shapes asked for fails straight away")
    func noShapes() {
        var configuration = HandCalibrationRecorder.Configuration()
        configuration.shapes = []

        #expect(HandCalibrationRecorder(configuration: configuration).progress == .failed(.tooFewReadings))
    }
}
