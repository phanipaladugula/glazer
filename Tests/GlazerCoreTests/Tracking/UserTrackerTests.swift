import Testing

@testable import GlazerCore

@Suite("UserTracker")
struct UserTrackerTests {
    @Test("With no faces, there's no user")
    func noFaces() {
        var tracker = UserTracker()
        #expect(tracker.update(with: frame(at: 0)) == .noFace)
    }

    @Test("The nearest face is the user, not someone behind them")
    func nearestFace() {
        var tracker = UserTracker()
        let user = face(x: 0.5, size: 0.35)
        let behind = face(x: 0.2, size: 0.12)

        #expect(tracker.update(with: frame(at: 0, behind, user)) == .user(user))
    }

    @Test("Faces too small or too uncertain are ignored")
    func ignoresWeakFaces() {
        var tracker = UserTracker()
        let distant = face(size: 0.08)
        let unsure = face(size: 0.3, confidence: 0.3)

        #expect(tracker.update(with: frame(at: 0, distant, unsure)) == .noFace)
    }

    @Test("Once locked, the user is followed even if someone nearer appears")
    func followsLockedFace() {
        var tracker = UserTracker()
        let user = face(x: 0.5, size: 0.3)
        _ = tracker.update(with: frame(at: 0, user))

        let movedUser = face(x: 0.52, size: 0.3)
        let leaningIn = face(x: 0.15, size: 0.45)
        #expect(tracker.update(with: frame(at: 0.1, leaningIn, movedUser)) == .user(movedUser))
    }

    @Test("A brief dropout holds; a long one lets go")
    func holdThenRelease() {
        var tracker = UserTracker()
        _ = tracker.update(with: frame(at: 0, face()))

        #expect(tracker.update(with: frame(at: 0.3)) == .holding)
        #expect(tracker.update(with: frame(at: 0.7)) == .noFace)
    }

    @Test("After letting go, the nearest face is picked again")
    func reacquires() {
        var tracker = UserTracker()
        _ = tracker.update(with: frame(at: 0, face(x: 0.5)))
        _ = tracker.update(with: frame(at: 1))

        let other = face(x: 0.2)
        #expect(tracker.update(with: frame(at: 1.1, other)) == .user(other))
    }

    // MARK: Face lock

    let verifier = IdentityVerifier(template: FaceTemplate(signatures: [People.alice]), threshold: 0.9)

    @Test("With face lock, only the enrolled user is followed")
    func faceLockPicksUser() {
        var tracker = UserTracker(verifier: verifier)
        let bob = face(x: 0.3, size: 0.4, signature: People.bob)
        let alice = face(x: 0.7, size: 0.3, signature: People.aliceAgain)

        #expect(tracker.update(with: frame(at: 0, bob, alice)) == .user(alice))
    }

    @Test("With face lock, strangers are not followed")
    func faceLockRejectsStrangers() {
        var tracker = UserTracker(verifier: verifier)
        #expect(tracker.update(with: frame(at: 0, face(signature: People.bob))) == .notRecognized)
    }

    @Test("With face lock, a frame without signatures is still being checked")
    func faceLockWaitsForSignatures() {
        var tracker = UserTracker(verifier: verifier)
        #expect(tracker.update(with: frame(at: 0, face())) == .checking)
    }

    @Test("Signatures are requested while searching and when a check is due")
    func signatureSchedule() {
        var tracker = UserTracker(verifier: verifier)
        #expect(tracker.needsSignatures(at: 0))

        _ = tracker.update(with: frame(at: 0, face(signature: People.alice)))
        #expect(!tracker.needsSignatures(at: 1))
        #expect(tracker.needsSignatures(at: 2))
    }

    @Test("A followed face that fails three checks in a row is dropped")
    func reverificationFails() {
        var tracker = UserTracker(verifier: verifier)
        _ = tracker.update(with: frame(at: 0, face(signature: People.alice)))

        #expect(tracker.update(with: frame(at: 2.1, face(signature: People.bob))) != .notRecognized)
        #expect(tracker.update(with: frame(at: 2.2, face(signature: People.bob))) != .notRecognized)
        #expect(tracker.update(with: frame(at: 2.3, face(signature: People.bob))) == .notRecognized)
    }

    @Test("One failed check, then a match, keeps the user")
    func singleMismatchForgiven() {
        var tracker = UserTracker(verifier: verifier)
        let alice = face(signature: People.alice)
        _ = tracker.update(with: frame(at: 0, alice))

        _ = tracker.update(with: frame(at: 2.1, face(signature: People.bob)))
        #expect(tracker.needsSignatures(at: 2.15))
        _ = tracker.update(with: frame(at: 2.2, alice))
        _ = tracker.update(with: frame(at: 4.3, face(signature: People.bob)))
        #expect(tracker.update(with: frame(at: 4.4, face(signature: People.bob))) != .notRecognized)
    }

    @Test("Without face lock, signatures are never requested")
    func noSignaturesWithoutLock() {
        #expect(!UserTracker().needsSignatures(at: 0))
    }
}
