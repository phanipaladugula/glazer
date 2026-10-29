import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("Placement")
struct PlacementTests {
    private let area = CGRect(x: 1000, y: 25, width: 2000, height: 1000)

    @Test("Content that fits keeps its size and is centred")
    func fits() {
        #expect(
            Placement.centred(CGSize(width: 800, height: 600), in: area)
                == CGRect(x: 1600, y: 225, width: 800, height: 600))
    }

    @Test("Content too big shrinks to fit, keeping its shape")
    func shrinks() {
        let placed = Placement.centred(CGSize(width: 4000, height: 1000), in: area)

        #expect(placed.width == 1800)
        #expect(placed.height == 450)
        #expect(abs(placed.midX - area.midX) <= 1)
        #expect(abs(placed.midY - area.midY) <= 1)
    }

    @Test("A smaller share can be asked for")
    func fraction() {
        let placed = Placement.centred(CGSize(width: 4000, height: 2000), in: area, within: 0.7)

        #expect(placed.width == 1400)
        #expect(placed.height == 700)
    }
}
