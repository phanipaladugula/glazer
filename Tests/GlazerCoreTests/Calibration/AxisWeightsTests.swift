import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("AxisWeights")
struct AxisWeightsTests {
    @Test("Displays side by side weight head turn")
    func sideBySide() {
        let weights = AxisWeights(arranging: [
            Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
        ])
        #expect(weights.yaw == 1)
        #expect(weights.pitch < 0.6)
    }

    @Test("Stacked displays weight head tilt")
    func stacked() {
        let weights = AxisWeights(arranging: [
            Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            Display(id: 5, name: "LG", frame: CGRect(x: -177, y: 982, width: 1920, height: 1080)),
        ])
        #expect(weights.pitch == 1)
        #expect(weights.yaw == 0.5)
    }

    @Test("Displays on a diagonal weight both")
    func diagonal() {
        let weights = AxisWeights(arranging: [
            Display(id: 1, name: "A", frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
            Display(id: 2, name: "B", frame: CGRect(x: 1000, y: 1000, width: 1000, height: 1000)),
        ])
        #expect(weights == AxisWeights(yaw: 1, pitch: 1))
    }

    @Test("One display, or none, falls back to side by side", arguments: [0, 1])
    func fallback(count: Int) {
        let displays = Array(
            [Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))].prefix(count))
        #expect(AxisWeights(arranging: displays) == .sideBySide)
    }
}

/// A real setup: an LG above a MacBook, and the calibration recorded on it, where the user
/// typed on the wrong display after shifting in their chair.
@Suite("Stacked displays, from a real calibration")
struct StackedDisplaysTests {
    let macBook = Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    let lg = Display(id: 5, name: "LG", frame: CGRect(x: -177, y: 982, width: 1920, height: 1080))
    let calibration = Calibration(points: [
        .init(displayID: 5, pose: HeadPose(yaw: -18.9, pitch: 3.2)),
        .init(displayID: 1, pose: HeadPose(yaw: -40.7, pitch: -19.2)),
    ])

    /// Faces each display for two seconds, after the user has shifted so the camera sees
    /// every yaw `shift` degrees off, and returns the display focused at the end.
    func focused(facing display: Display.ID, shift: Double, weights: AxisWeights) -> Display.ID? {
        var configuration = DisplayClassifier.Configuration()
        configuration.weights = weights
        var classifier = DisplayClassifier(calibration: calibration, configuration: configuration)
        classifier.setFocused(display == 5 ? 1 : 5)
        let base = calibration.pose(for: display) ?? HeadPose(yaw: 0, pitch: 0)
        let pose = HeadPose(yaw: base.yaw + shift, pitch: base.pitch)
        for step in 0...20 {
            classifier.update(with: pose, at: Double(step) * 0.1)
        }
        return classifier.focused
    }

    @Test("Weighted for the layout, a shifted user still gets the display they face", arguments: [-20.0, 0, 20])
    func layoutWeights(shift: Double) {
        let weights = AxisWeights(arranging: [macBook, lg])
        #expect(focused(facing: 5, shift: shift, weights: weights) == 5)
        #expect(focused(facing: 1, shift: shift, weights: weights) == 1)
    }

    @Test("The old side-by-side weighting picked the wrong display once the user shifted")
    func sideBySideWeightsFail() {
        let wrongForLG = focused(facing: 5, shift: -20, weights: .sideBySide) != 5
        let wrongForMacBook = focused(facing: 1, shift: 20, weights: .sideBySide) != 1
        #expect(wrongForLG && wrongForMacBook)
    }
}
