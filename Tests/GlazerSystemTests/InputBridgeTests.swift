import AppKit
import CoreGraphics
import GlazerCore
import Testing

@testable import GlazerSystem

@Suite("Input forwarding and replay")
@MainActor
struct InputBridgeTests {
    /// `input` replayed as a Core Graphics event, then read back as the forwarder would.
    private func roundTrip(_ input: InputEvent, buttons: Set<Int> = []) throws -> InputEvent? {
        let event = try #require(
            InputReplayer.event(for: input, at: CGPoint(x: 100, y: 100), buttons: buttons, source: nil))
        return InputForwarder.input(from: event.type, event)
    }

    @Test("Keys survive the trip, with modifiers and repeats")
    func keys() throws {
        let flags = CGEventFlags.maskCommand.rawValue
        for input in [
            InputEvent.key(code: 9, isDown: true, flags: flags, isRepeat: false),
            .key(code: 9, isDown: false, flags: flags, isRepeat: false),
            .key(code: 0, isDown: true, flags: 0, isRepeat: true),
        ] {
            let back = try roundTrip(input)
            guard case .key(let code, let isDown, let backFlags, let isRepeat) = back,
                case .key(let wantCode, let wantDown, let wantFlags, let wantRepeat) = input
            else {
                Issue.record("Expected a key, got \(String(describing: back))")
                continue
            }
            #expect(code == wantCode && isDown == wantDown && isRepeat == wantRepeat)
            #expect(backFlags & flags == wantFlags & flags)
        }
    }

    @Test("Modifier changes survive the trip")
    func modifiers() throws {
        let back = try roundTrip(.modifiers(code: 56, flags: CGEventFlags.maskShift.rawValue))
        guard case .modifiers(let code, let flags) = back else {
            Issue.record("Expected modifiers, got \(String(describing: back))")
            return
        }
        #expect(code == 56)
        #expect(flags & CGEventFlags.maskShift.rawValue != 0)
    }

    @Test("Buttons survive the trip, with click counts")
    func buttons() throws {
        for input in [
            InputEvent.button(0, isDown: true, clicks: 2, flags: 0), .button(1, isDown: false, clicks: 1, flags: 0),
            .button(2, isDown: true, clicks: 1, flags: 0),
        ] {
            let back = try roundTrip(input)
            guard case .button(let number, let isDown, let clicks, _) = back,
                case .button(let wantNumber, let wantDown, let wantClicks, _) = input
            else {
                Issue.record("Expected a button, got \(String(describing: back))")
                continue
            }
            #expect(number == wantNumber && isDown == wantDown && clicks == wantClicks)
        }
    }

    @Test("Movement keeps its deltas, and drags while a button is held")
    func movement() throws {
        let input = InputEvent.move(dx: 12, dy: -5, flags: 0)
        let event = try #require(
            InputReplayer.event(for: input, at: CGPoint(x: 100, y: 100), buttons: [0], source: nil))

        #expect(event.type == .leftMouseDragged)
        #expect(InputForwarder.input(from: event.type, event) == input)
        #expect(try #require(InputReplayer.event(for: input, at: .zero, buttons: [], source: nil)).type == .mouseMoved)
    }

    @Test("Scrolls survive the trip")
    func scroll() throws {
        let back = try roundTrip(.scroll(dx: 0, dy: 3, isContinuous: false, phase: 0, momentum: 0))
        guard case .scroll(_, let dy, let isContinuous, _, _) = back else {
            Issue.record("Expected a scroll, got \(String(describing: back))")
            return
        }
        #expect(dy == 3)
        #expect(!isContinuous)
    }

    @Test("Replayed events carry the marker, so they're never forwarded back")
    func marker() {
        #expect(InputReplayer.marker == 0x474C_5A52)
    }

    @Test("The pointer is kept on a display")
    func clamp() {
        let main = CGDisplayBounds(CGMainDisplayID())
        let outside = CGPoint(x: main.maxX + 10_000, y: main.midY)

        #expect(NSScreen.screens.contains { _ in true })
        let clamped = InputReplayer.clamp(outside)
        #expect(clamped.x < outside.x)
        #expect(InputReplayer.clamp(CGPoint(x: main.midX, y: main.midY)) == CGPoint(x: main.midX, y: main.midY))
    }
}

@Suite("Clipboard bridge")
@MainActor
struct ClipboardBridgeTests {
    @Test("Shareable contents round-trip through a pasteboard; private types stay")
    func roundTrip() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("glazer-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        pasteboard.setData(Data([1, 2]), forType: NSPasteboard.PasteboardType("com.example.private"))

        let contents = try #require(ClipboardBridge.read(from: pasteboard))
        #expect(contents.items == [["public.utf8-plain-text": Data("hello".utf8)]])

        let other = NSPasteboard(name: NSPasteboard.Name("glazer-tests-\(UUID())"))
        defer { other.releaseGlobally() }
        let count = ClipboardBridge.write(contents, to: other)
        #expect(count == ClipboardBridge.changeCount(of: other))
        #expect(other.string(forType: .string) == "hello")
    }

    @Test("An empty clipboard has nothing to share")
    func empty() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("glazer-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        #expect(ClipboardBridge.read(from: pasteboard) == nil)
    }
}
