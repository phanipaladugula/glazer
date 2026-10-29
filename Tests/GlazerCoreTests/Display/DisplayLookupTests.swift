import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("Display lookup")
struct DisplayLookupTests {
    let displays = [
        Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
    ]

    @Test(
        "Finds the display under a point",
        arguments: [
            (CGPoint(x: 10, y: 10), CGDirectDisplayID(1)),
            (CGPoint(x: 2000, y: 1200), CGDirectDisplayID(2)),
        ])
    func contains(point: CGPoint, expected: CGDirectDisplayID) {
        #expect(displays.display(containing: point)?.id == expected)
    }

    @Test("A point on a shared edge belongs to the display on the right")
    func sharedEdge() {
        #expect(displays.display(containing: CGPoint(x: 1512, y: 10))?.id == 2)
    }

    @Test("A point outside every display finds nothing")
    func outside() {
        #expect(displays.display(containing: CGPoint(x: 100, y: 1200)) == nil)
    }
}

@Suite("Display")
struct DisplayTests {
    @Test("The display at the origin has the menu bar")
    func menuBar() {
        let main = Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let other = Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

        #expect(main.hasMenuBar)
        #expect(!other.hasMenuBar)
    }

    @Test(
        "Built-in panels get a short name; others keep theirs",
        arguments: [
            ("Built-in Retina Display", "Built-in"),
            ("Built-in Liquid Retina XDR Display", "Built-in"),
            ("LG ULTRAFINE", "LG ULTRAFINE"),
        ])
    func shortName(name: String, expected: String) {
        let display = Display(id: 1, name: name, frame: .zero)
        #expect(display.shortName == expected)
    }
}

@Suite("Nearest display")
struct NearestDisplayTests {
    let displays = [
        Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
    ]

    @Test("A point inside a display is that display")
    func inside() {
        #expect(displays.display(nearest: CGPoint(x: 2000, y: 100))?.id == 2)
    }

    @Test("The top row of pixels, outside every half-open frame, is the display below it")
    func topRow() {
        #expect(displays.display(containing: CGPoint(x: 100, y: 982)) == nil)
        #expect(displays.display(nearest: CGPoint(x: 100, y: 982))?.id == 1)
    }

    @Test("No displays, no display")
    func none() {
        #expect([Display]().display(nearest: .zero) == nil)
    }
}
