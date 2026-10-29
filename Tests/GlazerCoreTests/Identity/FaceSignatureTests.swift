import Testing

@testable import GlazerCore

@Suite("FaceSignature")
struct FaceSignatureTests {
    @Test("A signature is identical to itself")
    func identical() {
        #expect(abs(People.alice.similarity(to: People.alice) - 1) < 1e-6)
    }

    @Test("The same person is more similar than a different one")
    func samePerson() {
        #expect(People.alice.similarity(to: People.aliceAgain) > People.alice.similarity(to: People.bob))
    }

    @Test("Signatures of different lengths never match")
    func mismatchedLength() {
        #expect(People.alice.similarity(to: FaceSignature(values: [1, 0])) == 0)
    }

    @Test("A template from another version is stale")
    func staleTemplate() {
        #expect(FaceTemplate(signatures: [People.alice]).isCurrent)
        #expect(!FaceTemplate(signatures: [People.alice], version: 0).isCurrent)
        #expect(!FaceTemplate(signatures: []).isCurrent)
    }
}
