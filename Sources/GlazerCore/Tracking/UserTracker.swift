import CoreGraphics
import Foundation

/// Picks out the user from all the faces in view, and follows them from frame to frame.
///
/// Without face lock, the user is the nearest face (the largest in the image), and once
/// found they are followed by position, so someone walking past doesn't take over. With
/// face lock, a face must also match the enrolled signature before it is followed, and
/// it is checked again every few seconds.
///
/// When the tracker isn't sure, it says so instead of guessing.
public struct UserTracker: Sendable {
    public struct Configuration: Sendable {
        /// Faces covering less of the image than this are ignored. At 0.012, a face must
        /// be roughly 11% of the image's width: about the size of someone within a metre
        /// or so of a laptop camera.
        public var minimumFaceArea: Double = 0.012
        /// Faces the detector is less sure of are ignored.
        public var minimumConfidence: Double = 0.5
        /// How much a face must overlap the user's last position to be the same person.
        public var minimumOverlap: Double = 0.2
        /// How long the user can disappear (a blink of the detector, a hand in front of
        /// the face) before the tracker lets go.
        public var holdDuration: TimeInterval = 0.6
        /// With face lock, how often the followed face is checked again.
        public var reverifyInterval: TimeInterval = 2.0
        /// With face lock, how many checks in a row the followed face must fail before the
        /// tracker lets go. One poorly lit frame shouldn't drop the user.
        public var allowedMismatches = 3

        public init() {}
    }

    public enum Outcome: Equatable, Sendable {
        /// The user, in this frame.
        case user(DetectedFace)
        /// The user wasn't found in this frame but was seen moments ago.
        case holding
        /// No usable face is in view.
        case noFace
        /// Faces are in view, but this frame has no signatures to check them against
        /// the enrolled user. The next frame will.
        case checking
        /// Faces are in view, but none matches the enrolled user.
        case notRecognized
    }

    public let configuration: Configuration
    public var verifier: IdentityVerifier?

    private var lockedBounds: CGRect?
    private var lastSeen: TimeInterval = -.infinity
    private var lastVerified: TimeInterval = -.infinity
    private var mismatches = 0

    public init(configuration: Configuration = Configuration(), verifier: IdentityVerifier? = nil) {
        self.configuration = configuration
        self.verifier = verifier
    }

    /// Whether the next frame should include face signatures.
    ///
    /// Signatures are only needed with face lock, and only while searching for the user
    /// or when a check is due. Skipping them otherwise keeps CPU use low.
    public func needsSignatures(at timestamp: TimeInterval) -> Bool {
        guard verifier != nil else { return false }
        return lockedBounds == nil || timestamp - lastVerified >= configuration.reverifyInterval
    }

    public mutating func update(with frame: Frame) -> Outcome {
        let candidates = frame.faces.filter {
            $0.area >= configuration.minimumFaceArea && $0.confidence >= configuration.minimumConfidence
        }

        if let lockedBounds, let face = followed(in: candidates, from: lockedBounds) {
            return confirm(face, at: frame.timestamp)
        }

        if lockedBounds != nil, frame.timestamp - lastSeen < configuration.holdDuration {
            return .holding
        }

        reset()
        return acquire(from: candidates, at: frame.timestamp)
    }

    /// Lets go of the user, so the next frame starts a fresh search.
    public mutating func reset() {
        lockedBounds = nil
        lastSeen = -.infinity
        lastVerified = -.infinity
        mismatches = 0
    }

    private func followed(in candidates: [DetectedFace], from bounds: CGRect) -> DetectedFace? {
        candidates
            .map { ($0, $0.bounds.overlap(with: bounds)) }
            .filter { $0.1 >= configuration.minimumOverlap }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Keeps following `face`, checking its identity when a check is due.
    private mutating func confirm(_ face: DetectedFace, at timestamp: TimeInterval) -> Outcome {
        if let verifier, let signature = face.signature {
            if verifier.matches(signature) {
                mismatches = 0
                lastVerified = timestamp
            } else {
                mismatches += 1
                guard mismatches < configuration.allowedMismatches else {
                    reset()
                    return .notRecognized
                }
                // Keep following for now; the next frame checks again.
            }
        }
        lock(face, at: timestamp)
        return .user(face)
    }

    /// Starts following the nearest face that qualifies.
    private mutating func acquire(from candidates: [DetectedFace], at timestamp: TimeInterval) -> Outcome {
        guard !candidates.isEmpty else { return .noFace }
        let nearestFirst = candidates.sorted { $0.area > $1.area }

        guard let verifier else {
            lock(nearestFirst[0], at: timestamp)
            return .user(nearestFirst[0])
        }

        guard nearestFirst.contains(where: { $0.signature != nil }) else { return .checking }
        let match = nearestFirst.first { face in
            face.signature.map(verifier.matches) ?? false
        }
        guard let match else { return .notRecognized }

        lastVerified = timestamp
        lock(match, at: timestamp)
        return .user(match)
    }

    private mutating func lock(_ face: DetectedFace, at timestamp: TimeInterval) {
        lockedBounds = face.bounds
        lastSeen = timestamp
    }
}
