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
    /// stale instead of silently failing to match. Version 2 crops signatures to the exact
    /// face box.
    public static let currentVersion = 2

    /// The range a learned ``threshold`` is kept within.
    public static let thresholdRange: ClosedRange<Double> = 0.5...0.97

    public let version: Int
    public let signatures: [FaceSignature]

    /// The similarity a face must reach to count as the user, learned from enrolment.
    ///
    /// For each enrolled signature, it finds the closest match among the signatures taken
    /// at *other* head angles: how alike the user looks to themselves after turning. The
    /// threshold sits just below the weakest of those, so the user is accepted at any
    /// angle they enrolled at. Comparing across angles matters: samples at one angle are
    /// taken a moment apart and are near copies, and a threshold learned from them would
    /// reject the user as soon as the light changed.
    public let threshold: Double

    /// - Parameter groups: Signatures grouped by the head angle they were taken at.
    public init(groups: [[FaceSignature]], version: Int = FaceTemplate.currentVersion, margin: Double = 0.04) {
        self.version = version
        signatures = groups.flatMap { $0 }
        threshold = Self.learnThreshold(from: groups.filter { !$0.isEmpty }, margin: margin)
    }

    /// A template from signatures taken at a single angle.
    public init(signatures: [FaceSignature], version: Int = FaceTemplate.currentVersion, margin: Double = 0.04) {
        self.init(groups: signatures.map { [$0] }, version: version, margin: margin)
    }

    public var isCurrent: Bool {
        version == Self.currentVersion && !signatures.isEmpty
    }

    /// The closest similarity between `signature` and any enrolled signature.
    public func bestSimilarity(to signature: FaceSignature) -> Double {
        signatures.map { $0.similarity(to: signature) }.max() ?? 0
    }

    private static func learnThreshold(from groups: [[FaceSignature]], margin: Double) -> Double {
        var selfSimilarities: [Double] = []
        for (index, group) in groups.enumerated() {
            let others = groups.enumerated().filter { $0.offset != index }.flatMap(\.element)
            for signature in group {
                if let best = others.map({ signature.similarity(to: $0) }).max() {
                    selfSimilarities.append(best)
                }
            }
        }
        let weakest = selfSimilarities.min() ?? thresholdRange.upperBound
        return min(max(weakest - margin, thresholdRange.lowerBound), thresholdRange.upperBound)
    }
}

/// Decides whether a face belongs to the enrolled user.
public struct IdentityVerifier: Sendable {
    public let template: FaceTemplate

    /// The similarity a face must reach to count as the user.
    public let threshold: Double

    /// - Parameter threshold: Overrides the template's learned threshold.
    public init(template: FaceTemplate, threshold: Double? = nil) {
        self.template = template
        self.threshold = threshold ?? template.threshold
    }

    /// How closely `signature` matches the user, from −1 to 1.
    public func score(_ signature: FaceSignature) -> Double {
        template.bestSimilarity(to: signature)
    }

    public func matches(_ signature: FaceSignature) -> Bool {
        score(signature) >= threshold
    }
}
