import CoreGraphics
import Foundation
import Testing

@testable import GlazerCore

/// The user's face: centred at (0.5, 0.6), 0.2 wide and 0.25 high.
private let face = CGRect(x: 0.4, y: 0.475, width: 0.2, height: 0.25)

private func reading(x: Double, y: Double, size: Double = 0.15) -> HandReading {
    HandReading(features: features(bend: 0), centre: CGPoint(x: x, y: y), size: size, confidence: 0.9)
}

@Suite("User hand")
struct UserHandTests {
    @Test("A hand raised beside the face is the user's")
    func beside() {
        let hand = reading(x: 0.75, y: 0.6)

        #expect(UserHand.hand(of: face, among: [hand]) == hand)
    }

    @Test("A hand far to the side is someone else's")
    func farSide() {
        #expect(UserHand.hand(of: face, among: [reading(x: 0.5 + 0.2 * 3.2, y: 0.6)]) == nil)
    }

    @Test("A hand well above or below the face isn't the user's")
    func aboveAndBelow() {
        #expect(UserHand.hand(of: face, among: [reading(x: 0.5, y: 0.6 + 0.25 * 1.7)]) == nil)
        #expect(UserHand.hand(of: face, among: [reading(x: 0.5, y: 0.6 - 0.25 * 2.7)]) == nil)
        #expect(UserHand.hand(of: face, among: [reading(x: 0.5, y: 0.6 - 0.25 * 2)]) != nil)
    }

    @Test("A hand too small for the user's distance is someone further back")
    func tooSmall() {
        #expect(UserHand.hand(of: face, among: [reading(x: 0.7, y: 0.6, size: 0.03)]) == nil)
    }

    @Test("A hand far too big isn't a hand at all")
    func tooBig() {
        #expect(UserHand.hand(of: face, among: [reading(x: 0.7, y: 0.6, size: 0.5)]) == nil)
    }

    @Test("Of two possible hands, the one nearer the face wins")
    func nearest() {
        let near = reading(x: 0.65, y: 0.6)
        let far = reading(x: 0.9, y: 0.55)

        #expect(UserHand.hand(of: face, among: [far, near]) == near)
    }

    @Test("A face with no size matches no hand")
    func emptyFace() {
        #expect(UserHand.hand(of: .zero, among: [reading(x: 0.5, y: 0.5)]) == nil)
    }

    @Test("Offsets are in face widths and heights")
    func offset() {
        let offset = UserHand.offset(of: reading(x: 0.7, y: 0.35), from: face)

        #expect(abs(offset.x - 1) < 1e-9)
        #expect(abs(offset.y + 1) < 1e-9)
    }

    @Test("The search area surrounds the face and stays in the image")
    func searchArea() {
        let area = UserHand.searchArea(around: face)

        #expect(area.contains(CGPoint(x: face.midX, y: face.midY)))
        #expect(area.minX >= 0 && area.maxX <= 1 && area.minY >= 0 && area.maxY <= 1)

        let small = CGRect(x: 0.48, y: 0.5, width: 0.04, height: 0.05)
        let smallArea = UserHand.searchArea(around: small)
        #expect(smallArea.width < 0.4)
        #expect(smallArea.contains(CGPoint(x: 0.5 + 0.04 * 3, y: 0.525)))
    }
}

@Suite("Hand aim")
struct HandAimTests {
    /// Readings scattered a little around `centre`.
    private func around(_ x: Double, _ y: Double, count: Int = 10) -> [CGPoint] {
        (0..<count).map { CGPoint(x: x + 0.03 * Double($0 % 3 - 1), y: y + 0.02 * Double($0 % 2)) }
    }

    @Test("Positions held towards each display choose it")
    func chooses() throws {
        let aim = try HandAim.fit([1: around(-1.5, -0.5), 2: around(1.5, -0.5)])

        #expect(aim.display(for: CGPoint(x: -1.4, y: -0.4)) == 1)
        #expect(aim.display(for: CGPoint(x: 1.6, y: -0.6)) == 2)
    }

    @Test("A position between displays chooses neither")
    func between() throws {
        let aim = try HandAim.fit([1: around(-1.5, 0), 2: around(1.5, 0)])

        #expect(aim.display(for: CGPoint(x: 0.1, y: 0)) == nil)
    }

    @Test("A position far from every display chooses none")
    func far() throws {
        let aim = try HandAim.fit([1: around(-1, 0), 2: around(1, 0)])

        #expect(aim.display(for: CGPoint(x: -1, y: 3)) == nil)
    }

    @Test("Stacked displays are told apart by height")
    func stacked() throws {
        let aim = try HandAim.fit([1: around(0, 0.6), 2: around(0, -1.4)])

        #expect(aim.display(for: CGPoint(x: 0.05, y: 0.5)) == 1)
        #expect(aim.display(for: CGPoint(x: -0.05, y: -1.3)) == 2)
    }

    @Test("Displays held towards from the same place are refused")
    func tooClose() {
        #expect(throws: HandAim.Problem.tooClose(1, 2)) {
            try HandAim.fit([1: around(0, 0), 2: around(0.2, 0)])
        }
    }

    @Test("One display, or too few readings, can't be fitted")
    func tooFew() {
        #expect(throws: HandAim.Problem.tooFewDisplays) { try HandAim.fit([1: around(0, 0)]) }
        #expect(throws: HandAim.Problem.tooFewReadings) {
            try HandAim.fit([1: around(-1, 0), 2: around(1, 0, count: 2)])
        }
    }

    @Test("It knows which displays it covers")
    func covers() throws {
        let aim = try HandAim.fit([1: around(-1, 0), 2: around(1, 0)])
        let displays = [1, 2, 3].map { Display(id: $0, name: "\($0)", frame: .zero) }

        #expect(aim.covers(Array(displays.prefix(2))))
        #expect(!aim.covers(displays))
    }

    @Test("It survives saving")
    func codable() throws {
        let aim = try HandAim.fit([1: around(-1, 0), 2: around(1, 0)])
        let data = try JSONEncoder().encode(aim)

        #expect(try JSONDecoder().decode(HandAim.self, from: data) == aim)
    }
}

@Suite("Hand aim recorder")
struct HandAimRecorderTests {
    private let face = CGRect(x: 0.4, y: 0.475, width: 0.2, height: 0.25)

    /// Feeds an open hand at face offset (`dx`, `dy`), or nothing, at 12 frames a second.
    @discardableResult
    private func feed(
        _ recorder: inout HandAimRecorder, dx: Double?, dy: Double = 0, bend: Double = 0, from start: Double,
        for duration: Double
    ) -> Double {
        var time = start
        while time < start + duration {
            let hand = dx.map {
                HandReading(
                    features: features(bend: bend),
                    centre: CGPoint(x: face.midX + $0 * face.width, y: face.midY + dy * face.height),
                    size: 0.15, confidence: 0.9)
            }
            recorder.add(hand: hand, face: hand == nil ? nil : face, at: time)
            time += 1.0 / 12
        }
        return time
    }

    @Test("Holding the hand towards each display in turn gives an aim")
    func records() {
        var recorder = HandAimRecorder(displays: [7, 9], calibration: Hands.calibration)
        #expect(recorder.progress == .waiting(7))

        var time = feed(&recorder, dx: -1.5, from: 0, for: 2)
        #expect(recorder.progress == .waiting(9))
        #expect(recorder.fractionDone == 0.5)
        time = feed(&recorder, dx: nil, from: time, for: 0.6)
        feed(&recorder, dx: 1.5, from: time, for: 2)

        guard case .finished(let aim) = recorder.progress else {
            Issue.record("Expected an aim, got \(recorder.progress)")
            return
        }
        #expect(aim.display(for: CGPoint(x: -1.5, y: 0)) == 7)
        #expect(aim.display(for: CGPoint(x: 1.5, y: 0)) == 9)
        #expect(recorder.fractionDone == 1)
    }

    @Test("A fist doesn't count as holding the hand towards a display")
    func fistIgnored() {
        var recorder = HandAimRecorder(displays: [7, 9], calibration: Hands.calibration)
        feed(&recorder, dx: -1.5, bend: Hands.fist, from: 0, for: 3)

        #expect(recorder.progress == .waiting(7))
    }

    @Test("Recording shows progress, and starts again when the hand leaves")
    func restarts() {
        var recorder = HandAimRecorder(displays: [7, 9], calibration: Hands.calibration)
        let time = feed(&recorder, dx: -1.5, from: 0, for: 1.0)
        guard case .recording(7, let fraction) = recorder.progress else {
            Issue.record("Expected recording, got \(recorder.progress)")
            return
        }
        #expect(fraction > 0)
        #expect(recorder.fractionDone > 0 && recorder.fractionDone < 0.5)

        feed(&recorder, dx: nil, from: time, for: 0.6)
        #expect(recorder.progress == .waiting(7))
    }

    @Test("The same place for every display fails as too close")
    func samePlace() {
        var recorder = HandAimRecorder(displays: [7, 9], calibration: Hands.calibration)
        var time = feed(&recorder, dx: 1, from: 0, for: 2)
        time = feed(&recorder, dx: nil, from: time, for: 0.6)
        time = feed(&recorder, dx: 1, from: time, for: 2)

        #expect(recorder.progress == .failed(.tooClose(7, 9)))
        #expect(recorder.add(hand: nil, face: nil, at: time) == .failed(.tooClose(7, 9)))
    }

    @Test("No displays fails straight away")
    func noDisplays() {
        let recorder = HandAimRecorder(displays: [], calibration: Hands.calibration)

        #expect(recorder.progress == .failed(.tooFewDisplays))
        #expect(recorder.fractionDone == 1)
    }
}
