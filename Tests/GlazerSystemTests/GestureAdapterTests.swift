import Foundation
import Testing

@testable import GlazerSystem

@Suite("Screenshot store")
struct ScreenshotStoreTests {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    @Test("Names follow macOS's own screenshots")
    func names() {
        let name = ScreenshotStore.fileName(for: date)

        #expect(name.hasPrefix("Screenshot 20"))
        #expect(name.contains(" at "))
        #expect(name.hasSuffix(".png"))
        #expect(ScreenshotStore.fileName(for: date, attempt: 2).hasSuffix(" (2).png"))
    }

    @Test("Saving never replaces an existing file")
    func neverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "glazer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try ScreenshotStore.save(png: Data([1]), at: date, in: folder)
        let second = try ScreenshotStore.save(png: Data([2]), at: date, in: folder)

        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
        #expect(second.lastPathComponent.hasSuffix(" (2).png"))
    }

    @Test("The folder exists")
    func folder() {
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: ScreenshotStore.folder.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}

@Suite("Document opener")
struct DocumentOpenerTests {
    private let area = CGRect(x: 1000, y: 25, width: 2000, height: 1000)

    @Test("A window that fits keeps its size and is centred")
    func fits() {
        let placed = DocumentOpener.placement(of: CGSize(width: 800, height: 600), in: area)

        #expect(placed == CGRect(x: 1600, y: 225, width: 800, height: 600))
    }

    @Test("A window too big shrinks to 90%, keeping its shape")
    func shrinks() {
        let placed = DocumentOpener.placement(of: CGSize(width: 4000, height: 1000), in: area)

        #expect(placed.width == 1800)
        #expect(placed.height == 450)
        #expect(abs(placed.midX - area.midX) <= 1)
        #expect(abs(placed.midY - area.midY) <= 1)
    }
}
