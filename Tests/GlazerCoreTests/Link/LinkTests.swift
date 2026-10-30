import Foundation
import Testing

@testable import GlazerCore

@Suite("Link frames")
struct LinkFrameTests {
    @Test("Frames read back whole, however the bytes arrive")
    func roundTrip() throws {
        let grab = UUID()
        let frames = try [
            LinkFrame.encode(
                .hello(PeerIdentity(id: "A", name: "MacBook"), version: LinkMessage.version, proof: Data([1]))),
            LinkFrame.encode(.screenshot(grab: grab), payload: Data(repeating: 7, count: 5000)),
            LinkFrame.encode(.input(.move(dx: 3, dy: -2, flags: 0))),
        ]
        let stream = frames.reduce(Data(), +)

        var reader = LinkFrame.Reader()
        var read: [(message: LinkMessage, payload: Data)] = []
        // In awkward pieces, as TCP may deliver them.
        var index = stream.startIndex
        for size in [1, 3, 7, 100, 4096, 9000] where index < stream.endIndex {
            let end = min(index + size, stream.endIndex)
            read += try reader.add(stream[index..<end])
            index = end
        }
        read += try reader.add(stream[index...])

        #expect(
            read.map(\.message) == [
                .hello(PeerIdentity(id: "A", name: "MacBook"), version: 1, proof: Data([1])), .screenshot(grab: grab),
                .input(.move(dx: 3, dy: -2, flags: 0)),
            ])
        #expect(read[1].payload == Data(repeating: 7, count: 5000))
        #expect(read[0].payload.isEmpty)
    }

    @Test("An oversized frame is refused before it's read")
    func tooLarge() {
        var header = Data()
        header.append(contentsOf: withUnsafeBytes(of: UInt32(10).bigEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt32(LinkFrame.maximumPayload + 1).bigEndian, Array.init))
        var reader = LinkFrame.Reader()

        #expect(throws: LinkFrame.Failure.tooLarge) { try reader.add(header) }
        #expect(throws: LinkFrame.Failure.tooLarge) {
            try LinkFrame.encode(.heartbeat, payload: Data(count: LinkFrame.maximumPayload + 1))
        }
    }

    @Test("A frame that isn't a message is refused")
    func unreadable() {
        var frame = Data()
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(3).bigEndian, Array.init))
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian, Array.init))
        frame.append(Data("abc".utf8))
        var reader = LinkFrame.Reader()

        #expect(throws: LinkFrame.Failure.unreadable) { try reader.add(frame) }
    }
}

@Suite("Link proof")
struct LinkProofTests {
    @Test("A proof checks only with the same key, sender and receiver")
    func proof() {
        let key = Data(repeating: 1, count: 32)
        let proof = LinkProof.make(key: key, from: "A", to: "B")

        #expect(LinkProof.check(proof, key: key, from: "A", to: "B"))
        #expect(!LinkProof.check(proof, key: Data(repeating: 2, count: 32), from: "A", to: "B"))
        #expect(!LinkProof.check(proof, key: key, from: "B", to: "A"))
    }
}

@Suite("Presence")
struct PresenceTests {
    @Test("A Mac is faced only within a few degrees of one of its displays")
    func faced() {
        #expect(Presence(distance: 0).isFaced)
        #expect(Presence(distance: Presence.facedWithin).isFaced)
        #expect(!Presence(distance: 15).isFaced)
        #expect(!Presence(distance: nil).isFaced)
        #expect(Presence.unknown == Presence(isFaced: false, distance: nil))
    }
}

@Suite("Link arbiter")
struct LinkArbiterTests {
    @Test("Facing a linked Mac moves the user there after the dwell")
    func movesAfterDwell() {
        var arbiter = LinkArbiter()
        arbiter.updateLocal(Presence(distance: 20), at: 0)
        arbiter.update(peer: "B", Presence(distance: 1), at: 0)

        #expect(arbiter.decide(at: 0) == nil)
        #expect(arbiter.decide(at: 0.2) == nil)
        #expect(arbiter.decide(at: 0.5) == "B")
    }

    @Test("Facing this Mac again brings the user back at once")
    func comesBack() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 0), at: 0)
        arbiter.decide(at: 0)
        arbiter.decide(at: 1)
        #expect(arbiter.target == "B")

        arbiter.updateLocal(Presence(distance: 0), at: 1.1)
        #expect(arbiter.decide(at: 1.1) == nil)
    }

    @Test("Facing no Mac changes nothing")
    func nowhere() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 0), at: 0)
        arbiter.decide(at: 0)
        arbiter.decide(at: 1)

        arbiter.update(peer: "B", Presence(distance: 30), at: 1.5)
        arbiter.updateLocal(Presence(distance: 30), at: 1.5)
        #expect(arbiter.decide(at: 2) == "B")
    }

    @Test("Of two faced Macs, the more squarely faced wins")
    func squarest() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 5), at: 0)
        arbiter.update(peer: "C", Presence(distance: 1), at: 0)
        arbiter.decide(at: 0)

        #expect(arbiter.decide(at: 1) == "C")
        #expect(arbiter.peerIDs == ["B", "C"])
    }

    @Test("Old reports don't count")
    func stale() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 0), at: 0)

        arbiter.decide(at: 3)
        #expect(arbiter.decide(at: 4) == nil)
    }

    @Test("A glance shorter than the dwell doesn't move the user")
    func glance() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 0), at: 0)
        arbiter.decide(at: 0)
        arbiter.update(peer: "B", Presence(distance: 30), at: 0.2)
        arbiter.updateLocal(Presence(distance: 0), at: 0.2)
        arbiter.decide(at: 0.2)

        arbiter.updateLocal(Presence(distance: 30), at: 0.3)
        arbiter.update(peer: "B", Presence(distance: 0), at: 0.3)
        #expect(arbiter.decide(at: 0.5) == nil)
    }

    @Test("A Mac that leaves takes the user back here")
    func removal() {
        var arbiter = LinkArbiter()
        arbiter.update(peer: "B", Presence(distance: 0), at: 0)
        arbiter.decide(at: 0)
        arbiter.decide(at: 1)

        arbiter.remove(peer: "B")
        #expect(arbiter.target == nil)
        #expect(arbiter.peerIDs.isEmpty)
    }

    @Test("A chosen Mac holds until the user faces somewhere new")
    func choice() {
        var arbiter = LinkArbiter()
        arbiter.updateLocal(Presence(distance: 0), at: 0)
        arbiter.update(peer: "B", Presence(distance: 30), at: 0)
        arbiter.choose("B", at: 0)

        // Still facing this Mac, as when the shortcut was pressed: stays on B.
        #expect(arbiter.decide(at: 1) == "B")

        // Facing B, then this Mac again: back here.
        arbiter.updateLocal(Presence(distance: 30), at: 1.5)
        arbiter.update(peer: "B", Presence(distance: 0), at: 1.5)
        arbiter.decide(at: 1.5)
        arbiter.updateLocal(Presence(distance: 0), at: 2)
        #expect(arbiter.decide(at: 2) == nil)
    }
}

@Suite("Held input")
struct HeldInputTests {
    @Test("Everything held is released, and nothing else")
    func releases() {
        var held = HeldInput()
        held.record(.modifiers(code: 55, flags: 0x10_0000))
        held.record(.key(code: 9, isDown: true, flags: 0x10_0000, isRepeat: false))
        held.record(.key(code: 0, isDown: true, flags: 0x10_0000, isRepeat: false))
        held.record(.key(code: 0, isDown: false, flags: 0x10_0000, isRepeat: false))
        held.record(.button(0, isDown: true, clicks: 1, flags: 0x10_0000))
        held.record(.move(dx: 1, dy: 1, flags: 0))
        held.record(.scroll(dx: 0, dy: 3, isContinuous: true, phase: 0, momentum: 0))

        #expect(
            held.releases() == [
                .button(0, isDown: false, clicks: 1, flags: 0), .key(code: 9, isDown: false, flags: 0, isRepeat: false),
                .modifiers(code: 0, flags: 0),
            ])
        #expect(!held.isEmpty)
    }

    @Test("Nothing held, nothing to release")
    func empty() {
        var held = HeldInput()
        held.record(.button(1, isDown: true, clicks: 1, flags: 0))
        held.record(.button(1, isDown: false, clicks: 1, flags: 0))

        #expect(held.isEmpty)
        #expect(held.releases().isEmpty)
    }
}

@Suite("Clipboard contents")
struct ClipboardContentsTests {
    @Test("Only shared kinds of data are kept")
    func shareable() {
        let contents = ClipboardContents(items: [
            ["public.utf8-plain-text": Data("hi".utf8), "public.file-url": Data("file:///x".utf8)],
            ["com.example.private": Data([1])],
        ])

        #expect(contents.shareable == ClipboardContents(items: [["public.utf8-plain-text": Data("hi".utf8)]]))
        #expect(contents.size == 2 + 9 + 1)
    }

    @Test("Contents survive encoding")
    func codable() throws {
        let contents = ClipboardContents(items: [["public.png": Data(repeating: 1, count: 100)]])

        #expect(try ClipboardContents.decode(contents.encoded()) == contents)
    }
}
