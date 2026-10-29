import Foundation

/// A numeric description of a face, used to tell the enrolled user from other people.
///
/// A signature is a vector of numbers computed from an image of the face. It can't be
/// turned back into a photo, but it is still biometric data: Glazer keeps it in memory or
/// in the Keychain, never in plain files, and never sends it anywhere.
public struct FaceSignature: Equatable, Sendable, Codable {
    public let values: [Float]

    public init(values: [Float]) {
        self.values = values
    }

    /// Cosine similarity with `other`: 1 for the same direction, 0 for unrelated, −1 for
    /// opposite. Returns 0 when the signatures have different lengths, which happens only
    /// if the extractor changed between enrolment and now.
    public func similarity(to other: FaceSignature) -> Double {
        guard values.count == other.values.count, !values.isEmpty else { return 0 }
        var dot: Float = 0
        var selfSquared: Float = 0
        var otherSquared: Float = 0
        for index in values.indices {
            let a = values[index]
            let b = other.values[index]
            dot += a * b
            selfSquared += a * a
            otherSquared += b * b
        }
        let magnitude = (selfSquared * otherSquared).squareRoot()
        return magnitude > 0 ? Double(dot / magnitude) : 0
    }
}

/// The signatures enrolled for the user, taken from several angles.
public struct FaceTemplate: Equatable, Sendable, Codable {
    /// Bumped when the signature format changes, so an old template is recognised as
    /// stale instead of silently failing to match.
    public static let currentVersion = 1

    public let version: Int
    public let signatures: [FaceSignature]

    public init(signatures: [FaceSignature], version: Int = FaceTemplate.currentVersion) {
        self.version = version
        self.signatures = signatures
    }

    public var isCurrent: Bool {
        version == Self.currentVersion && !signatures.isEmpty
    }

    /// The closest similarity between `signature` and any enrolled signature.
    public func bestSimilarity(to signature: FaceSignature) -> Double {
        signatures.map { $0.similarity(to: signature) }.max() ?? 0
    }
}

/// Decides whether a face belongs to the enrolled user.
public struct IdentityVerifier: Sendable {
    public let template: FaceTemplate

    /// The similarity a face must reach to count as the user.
    public let threshold: Double

    public init(template: FaceTemplate, threshold: Double = 0.82) {
        self.template = template
        self.threshold = threshold
    }

    public func matches(_ signature: FaceSignature) -> Bool {
        template.bestSimilarity(to: signature) >= threshold
    }
}
