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

    @Test("The threshold sits just below how alike the user looks to themselves")
    func learnedThreshold() {
        let template = FaceTemplate(
            signatures: [People.alice, People.aliceAgain, FaceSignature(values: [0.9, 0.3, 0.1, 0.15])],
            margin: 0.04)
        let weakest = People.alice.similarity(to: People.aliceAgain) - 0.04

        #expect(template.threshold <= weakest + 1e-9)
        #expect(template.threshold > People.alice.similarity(to: People.bob))
    }

    @Test("The learned threshold accepts the user and rejects someone else")
    func learnedThresholdDecides() {
        let verifier = IdentityVerifier(template: FaceTemplate(signatures: [People.alice, People.aliceAgain]))
        #expect(verifier.matches(People.aliceAgain))
        #expect(!verifier.matches(People.bob))
    }

    @Test("A threshold never leaves its safe range", arguments: [[People.alice], [People.alice, People.bob]])
    func thresholdRange(signatures: [FaceSignature]) {
        #expect(FaceTemplate.thresholdRange.contains(FaceTemplate(signatures: signatures).threshold))
    }

    @Test("Grouped by angle, the threshold compares across angles, not near-copies")
    func crossAngleThreshold() {
        let straight = [FaceSignature(values: [1, 0, 0]), FaceSignature(values: [1, 0.01, 0])]
        let turned = [FaceSignature(values: [0.8, 0.6, 0]), FaceSignature(values: [0.8, 0.61, 0])]
        let template = FaceTemplate(groups: [straight, turned], margin: 0)
        let acrossAngles = straight[0].similarity(to: turned[0])

        #expect(abs(template.threshold - acrossAngles) < 0.01)
        #expect(template.threshold < straight[0].similarity(to: straight[1]))
    }

    @Test("Templates from before the exact-box crop are stale")
    func versionOneIsStale() {
        #expect(!FaceTemplate(signatures: [People.alice], version: 1).isCurrent)
    }
}
