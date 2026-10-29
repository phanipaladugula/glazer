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
}
