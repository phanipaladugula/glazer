import CoreGraphics

extension Array where Element == Display {
    /// The display whose frame contains `point`, in global screen coordinates.
    ///
    /// Frames are half-open, so a point on the shared edge of two displays belongs to
    /// exactly one of them.
    public func display(containing point: CGPoint) -> Display? {
        first { display in
            let frame = display.frame
            return point.x >= frame.minX && point.x < frame.maxX
                && point.y >= frame.minY && point.y < frame.maxY
        }
    }

    /// The display containing `point`, or failing that the display nearest to it.
    ///
    /// The pointer can sit just outside every half-open frame, such as on the top row of
    /// pixels, where its y equals the frame's maxY.
    public func display(nearest point: CGPoint) -> Display? {
        display(containing: point) ?? self.min { $0.frame.distance(to: point) < $1.frame.distance(to: point) }
    }
}

extension CGRect {
    /// The distance from `point` to the nearest point of this rectangle; 0 inside it.
    func distance(to point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
