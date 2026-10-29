import Testing

@testable import GlazerCore

@Suite("FocusPolicy")
struct FocusPolicyTests {
    func policy(_ mode: SwitchMode) -> FocusPolicy {
        FocusPolicy(mode: mode, keyboardDisplay: macBookID)
    }

    // MARK: Automatic

    @Test("Automatic: facing the monitor moves only the pointer")
    func automaticPointerFirst() {
        var policy = policy(.automatic)
        #expect(policy.userFaces(monitorID) == [.movePointer(monitorID)])
        #expect(policy.keyboardDisplay == macBookID)
        #expect(policy.pendingDisplay == monitorID)
    }

    @Test("Automatic: starting to type moves keyboard focus before the key")
    func automaticFreshStart() {
        var policy = policy(.automatic)
        _ = policy.userFaces(monitorID)
        #expect(policy.keyPressed(at: 10) == [.moveKeyboardFocus(monitorID)])
        #expect(policy.keyboardDisplay == monitorID)
        #expect(policy.keyPressed(at: 10.1) == [])
    }

    @Test("Automatic: talking towards the monitor without typing moves no keyboard focus")
    func automaticTalking() {
        var policy = policy(.automatic)
        _ = policy.userFaces(monitorID)
        #expect(policy.userFaces(macBookID) == [.movePointer(macBookID)])
        #expect(policy.pendingDisplay == nil)
        #expect(policy.keyPressed(at: 10) == [])
        #expect(policy.keyboardDisplay == macBookID)
    }

    @Test("Automatic: typing while talking towards the monitor stays on the MacBook")
    func automaticTypingWhileTalking() {
        var policy = policy(.automatic)
        _ = policy.keyPressed(at: 9.0)
        _ = policy.keyPressed(at: 9.4)
        _ = policy.userFaces(monitorID)

        // Still the same burst of typing: every gap is under the pause.
        for time in stride(from: 9.8, through: 14.0, by: 0.3) {
            #expect(policy.keyPressed(at: time) == [])
        }
        #expect(policy.keyboardDisplay == macBookID)
    }

    @Test("Automatic: a pause before typing makes it a fresh start")
    func automaticPauseThenType() {
        var policy = policy(.automatic)
        _ = policy.keyPressed(at: 9.0)
        _ = policy.userFaces(monitorID)
        #expect(policy.keyPressed(at: 9.5) == [])
        #expect(policy.keyPressed(at: 11.5) == [.moveKeyboardFocus(monitorID)])
    }

    @Test("Automatic: moving the pointer by hand cancels the pending switch")
    func automaticManualPointer() {
        var policy = policy(.automatic)
        _ = policy.userFaces(monitorID)
        policy.userMovedPointer(to: macBookID)
        #expect(policy.keyPressed(at: 10) == [])
    }

    // MARK: Hold key

    @Test("Hold key: facing the monitor does nothing without the key")
    func holdKeyIdle() {
        var policy = policy(.holdKey)
        #expect(policy.userFaces(monitorID) == [])
        #expect(policy.keyPressed(at: 10) == [])
        #expect(policy.keyboardDisplay == macBookID)
    }

    @Test("Hold key: pressing it while facing the monitor switches both")
    func holdKeyPress() {
        var policy = policy(.holdKey)
        _ = policy.userFaces(monitorID)
        #expect(policy.holdKeyChanged(isDown: true) == [.movePointer(monitorID), .moveKeyboardFocus(monitorID)])
        #expect(policy.keyboardDisplay == monitorID)
    }

    @Test("Hold key: turning while it's held switches")
    func holdKeyWhileTurning() {
        var policy = policy(.holdKey)
        _ = policy.holdKeyChanged(isDown: true)
        #expect(policy.userFaces(monitorID) == [.movePointer(monitorID), .moveKeyboardFocus(monitorID)])
    }

    @Test("Hold key: releasing it stops switching")
    func holdKeyReleased() {
        var policy = policy(.holdKey)
        _ = policy.holdKeyChanged(isDown: true)
        _ = policy.holdKeyChanged(isDown: false)
        #expect(policy.userFaces(monitorID) == [])
    }

    // MARK: Immediate

    @Test("Immediate: facing the monitor moves both at once")
    func immediate() {
        var policy = policy(.immediate)
        #expect(policy.userFaces(monitorID) == [.movePointer(monitorID), .moveKeyboardFocus(monitorID)])
        #expect(policy.keyPressed(at: 10) == [])
    }

    @Test("Only immediate mode works without the keyboard", arguments: SwitchMode.allCases)
    func needsKeyboard(mode: SwitchMode) {
        #expect(FocusPolicy(mode: mode, keyboardDisplay: nil).needsKeyboard == (mode != .immediate))
    }
}
