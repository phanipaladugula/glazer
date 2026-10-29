/// The head poses that face one display: the smallest convex shape around the poses
/// recorded at its centre and corners.
///
/// A single pose can only say where the middle of a display is. Looking at its edge is a
/// smaller turn than looking at its middle, so near the edge between two displays, the
/// other display's middle can be nearer. The region knows where each display ends, so a
/// pose anywhere on it counts as facing it.
public struct PoseRegion: Equatable, Sendable {
    /// The corners of the region, counter-clockwise by yaw and pitch. One pose for a region
    /// recorded only at the centre, two for poses along a line.
    public let vertices: [HeadPose]

    public init(poses: [HeadPose]) {
        vertices = Self.hull(of: poses)
    }

    /// Whether `pose` is on the region.
    public func contains(_ pose: HeadPose, weights: AxisWeights) -> Bool {
        distance(to: pose, weights: weights) == 0
    }

    /// The weighted distance from `pose` to the nearest part of the region, in degrees:
    /// 0 on the region.
    public func distance(to pose: HeadPose, weights: AxisWeights) -> Double {
        let point = Self.point(pose, weights)
        let corners = vertices.map { Self.point($0, weights) }
        switch corners.count {
        case 0:
            return .infinity
        case 1:
            return Self.length(point - corners[0])
        default:
            // Weighting stretches the axes, which keeps the corners in order, so the region
            // is still convex: it contains a point that is on the left of every edge.
            let edges = corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
            if corners.count > 2, edges.allSatisfy({ Self.cross($0.1 - $0.0, point - $0.0) >= 0 }) {
                return 0
            }
            return edges.map { Self.distance(from: point, toSegment: $0) }.min() ?? .infinity
        }
    }

    // MARK: Geometry

    private struct Point {
        var x: Double
        var y: Double

        static func - (lhs: Point, rhs: Point) -> Point {
            Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
        }
    }

    private static func point(_ pose: HeadPose, _ weights: AxisWeights) -> Point {
        Point(x: pose.yaw * weights.yaw, y: pose.pitch * weights.pitch)
    }

    private static func cross(_ a: Point, _ b: Point) -> Double {
        a.x * b.y - a.y * b.x
    }

    private static func length(_ a: Point) -> Double {
        (a.x * a.x + a.y * a.y).squareRoot()
    }

    private static func distance(from point: Point, toSegment segment: (Point, Point)) -> Double {
        let direction = segment.1 - segment.0
        let lengthSquared = direction.x * direction.x + direction.y * direction.y
        guard lengthSquared > 0 else { return length(point - segment.0) }
        let offset = point - segment.0
        let along = min(max((offset.x * direction.x + offset.y * direction.y) / lengthSquared, 0), 1)
        let nearest = Point(x: segment.0.x + direction.x * along, y: segment.0.y + direction.y * along)
        return length(point - nearest)
    }

    /// The convex hull of `poses`, counter-clockwise, without repeated or collinear corners
    /// (Andrew's monotone chain).
    static func hull(of poses: [HeadPose]) -> [HeadPose] {
        let sorted = poses.sorted { ($0.yaw, $0.pitch) < ($1.yaw, $1.pitch) }
        var unique: [HeadPose] = []
        for pose in sorted where unique.last != pose {
            unique.append(pose)
        }
        guard unique.count > 2 else { return unique }

        func turn(_ o: HeadPose, _ a: HeadPose, _ b: HeadPose) -> Double {
            (a.yaw - o.yaw) * (b.pitch - o.pitch) - (a.pitch - o.pitch) * (b.yaw - o.yaw)
        }
        func chain(_ poses: some Sequence<HeadPose>) -> [HeadPose] {
            var chain: [HeadPose] = []
            for pose in poses {
                while chain.count >= 2, turn(chain[chain.count - 2], chain[chain.count - 1], pose) <= 0 {
                    chain.removeLast()
                }
                chain.append(pose)
            }
            return chain
        }
        let lower = chain(unique)
        let upper = chain(unique.reversed())
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        // All the poses on one line: the hull is that line's two ends.
        return hull.count > 2 ? hull : [unique[0], unique[unique.count - 1]]
    }
}
