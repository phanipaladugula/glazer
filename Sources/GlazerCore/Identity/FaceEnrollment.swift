import Foundation

/// Builds a ``FaceTemplate`` from a short scan of the user's face.
///
/// The user turns their head slowly while looking at the camera. Enrolment collects
/// signatures from the left, the centre and the right, so the user is recognised whichever
/// display they face. It accepts only frames with exactly one clear face, and checks that
/// every sample looks like the same person, so a second person leaning in can't end up in
/// the template.
public struct FaceEnrollment: Sendable {
    public struct Configuration: Sendable {
        /// Yaw ranges, in degrees, that each need samples.
        public var yawRanges: [ClosedRange<Double>] = [-40 ... -8, -8...8, 8...40]
        /// Samples needed in each range.
        public var samplesPerRange = 4
        /// Minimum time between samples, so they aren't near-copies of one frame.
        public var sampleInterval: TimeInterval = 0.15
        /// The smallest face, as a share of the image, accepted for enrolment.
        public var minimumFaceArea: Double = 0.03
        /// The detector confidence needed for a sample.
        public var minimumConfidence: Double = 0.8
        /// Every new sample must be at least this similar to one already taken.
        public var minimumConsistency: Double = 0.6

        public init() {}
    }

    public enum Feedback: Equatable, Sendable {
        case lookAtCamera
        case moveCloser
        case onlyOnePerson
        /// Turn slowly so the remaining angles are covered.
        case turnSlowly
        /// The samples didn't look like one person. Enrolment started over.
        case restarted
        case done
    }

    public let configuration: Configuration
    public private(set) var feedback: Feedback = .lookAtCamera

    private var samples: [[FaceSignature]]
    private var lastSampleAt: TimeInterval = -.infinity

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        samples = Array(repeating: [], count: configuration.yawRanges.count)
    }

    /// Progress from 0 to 1.
    public var progress: Double {
        let needed = configuration.yawRanges.count * configuration.samplesPerRange
        let collected = samples.reduce(0) { $0 + min($1.count, configuration.samplesPerRange) }
        return needed > 0 ? Double(collected) / Double(needed) : 1
    }

    /// Progress for each yaw range, from 0 to 1. Useful for drawing a ring that fills in
    /// as each side is covered.
    public var rangeProgress: [Double] {
        samples.map { min(Double($0.count) / Double(configuration.samplesPerRange), 1) }
    }

    /// The finished template, once every range has its samples.
    public var template: FaceTemplate? {
        guard feedback == .done else { return nil }
        return FaceTemplate(groups: samples)
    }

    @discardableResult
    public mutating func add(_ frame: Frame) -> Feedback {
        guard feedback != .done else { return feedback }

        let faces = frame.faces.filter { $0.confidence >= configuration.minimumConfidence }
        guard faces.count <= 1 else { return set(.onlyOnePerson) }
        guard let face = faces.first, let signature = face.signature else { return set(.lookAtCamera) }
        guard face.area >= configuration.minimumFaceArea else { return set(.moveCloser) }
        guard frame.timestamp - lastSampleAt >= configuration.sampleInterval else { return feedback }

        // Compared with the closest sample so far, not the first: a face turned to the side
        // looks less like a straight-on one, but it looks like the sample next to it.
        let taken = samples.flatMap { $0 }
        if !taken.isEmpty,
            (taken.map { signature.similarity(to: $0) }.max() ?? 0) < configuration.minimumConsistency
        {
            samples = Array(repeating: [], count: configuration.yawRanges.count)
            return set(.restarted)
        }

        if let range = configuration.yawRanges.firstIndex(where: { $0.contains(face.pose.yaw) }),
            samples[range].count < configuration.samplesPerRange
        {
            samples[range].append(signature)
            lastSampleAt = frame.timestamp
        }

        let complete = samples.allSatisfy { $0.count >= configuration.samplesPerRange }
        return set(complete ? .done : .turnSlowly)
    }

    private mutating func set(_ feedback: Feedback) -> Feedback {
        self.feedback = feedback
        return feedback
    }
}
