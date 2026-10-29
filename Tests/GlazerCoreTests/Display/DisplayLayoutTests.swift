import CoreGraphics
import Testing

@testable import GlazerCore

@Suite("DisplayLayout")
struct DisplayLayoutTests {
    // A 1512×982 MacBook with a 2560×1440 monitor to its right, bottoms aligned.
    let macBook = Display(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    let monitor = Display(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

    @Test("No displays produce no items")
    func empty() {
        let layout = DisplayLayout(displays: [], fitting: CGSize(width: 100, height: 100))
        #expect(layout.items.isEmpty)
    }

    @Test("A zero-sized area produces no items")
    func zeroSize() {
        let layout = DisplayLayout(displays: [macBook], fitting: .zero)
        #expect(layout.items.isEmpty)
    }

    @Test("A single display fills the area and is centred")
    func single() throws {
        let layout = DisplayLayout(displays: [monitor], fitting: CGSize(width: 200, height: 200))
        let rect = try #require(layout.items.first).rect

        #expect(rect.width == 200)
        #expect(rect.height == 112.5)
        #expect(rect.midY == 100)
    }

    @Test("Displays keep their relative size and position")
    func arrangement() throws {
        let layout = DisplayLayout(displays: [macBook, monitor], fitting: CGSize(width: 4072, height: 1440))
        let left = try #require(layout.items.first { $0.id == 1 }).rect
        let right = try #require(layout.items.first { $0.id == 2 }).rect

        #expect(left == CGRect(x: 0, y: 458, width: 1512, height: 982))
        #expect(right == CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    }

    @Test("Y is flipped: a display above in screen space is drawn above")
    func flipped() throws {
        let above = Display(id: 3, name: "Above", frame: CGRect(x: 0, y: 982, width: 1512, height: 982))
        let layout = DisplayLayout(displays: [macBook, above], fitting: CGSize(width: 1512, height: 1964))
        let top = try #require(layout.items.first { $0.id == 3 }).rect
        let bottom = try #require(layout.items.first { $0.id == 1 }).rect

        #expect(top.minY == 0)
        #expect(bottom.minY == 982)
    }

    @Test("Spacing insets each display by half the gap")
    func spacing() throws {
        let layout = DisplayLayout(
            displays: [macBook, monitor], fitting: CGSize(width: 4072, height: 1440), spacing: 8)
        let left = try #require(layout.items.first { $0.id == 1 }).rect
        let right = try #require(layout.items.first { $0.id == 2 }).rect

        #expect(right.minX - left.maxX == 8)
    }
}
