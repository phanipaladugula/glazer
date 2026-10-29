import Testing

@testable import GlazerCore

@Suite("TypingGuard")
struct TypingGuardTests {
    /// A guard with focus on the MacBook, whose user last typed at 9.8 s.
    func typingOnMacBook() -> TypingGuard {
        var typingGuard = TypingGuard(focusedDisplay: macBookID)
        typingGuard.keyPressed(at: 9.8)
        return typingGuard
    }

    @Test("Facing another display while not typing switches at once")
    func switchesWhenIdle() {
        var typingGuard = TypingGuard(focusedDisplay: macBookID)
        #expect(typingGuard.userFaces(monitorID, at: 10) == monitorID)
        #expect(typingGuard.heldDisplay == nil)
    }

    @Test("Facing the focused display changes nothing")
    func sameDisplay() {
        var typingGuard = TypingGuard(focusedDisplay: macBookID)
        #expect(typingGuard.userFaces(macBookID, at: 10) == nil)
    }

    @Test("While typing, the switch is held back")
    func holdsWhileTyping() {
        var typingGuard = typingOnMacBook()
        #expect(typingGuard.userFaces(monitorID, at: 10) == nil)
        #expect(typingGuard.heldDisplay == monitorID)
    }

    @Test("Typing on while facing another display never switches")
    func typingContinues() {
        var typingGuard = typingOnMacBook()
        _ = typingGuard.userFaces(monitorID, at: 10)
        for time in stride(from: 10.0, through: 15.0, by: 0.4) {
            typingGuard.keyPressed(at: time)
            #expect(typingGuard.release(at: time + 0.1) == nil)
        }
    }

    @Test("Once typing pauses, the held switch goes ahead, once")
    func releasesAfterPause() {
        var typingGuard = typingOnMacBook()
        _ = typingGuard.userFaces(monitorID, at: 10)
        #expect(typingGuard.release(at: 10.5) == nil)
        #expect(typingGuard.release(at: 10.8) == monitorID)
        #expect(typingGuard.release(at: 11) == nil)
    }

    @Test("Facing back before the pause drops the held switch")
    func droppedWhenFacingBack() {
        var typingGuard = typingOnMacBook()
        _ = typingGuard.userFaces(monitorID, at: 10)
        #expect(typingGuard.userFaces(macBookID, at: 10.3) == nil)
        #expect(typingGuard.release(at: 12) == nil)
    }

    @Test("Moving focus by hand drops the held switch")
    func userFocusWins() {
        var typingGuard = typingOnMacBook()
        _ = typingGuard.userFaces(monitorID, at: 10)
        typingGuard.userFocused(macBookID)
        #expect(typingGuard.release(at: 12) == nil)
    }
}
