import CoreGraphics

/// The arrangement of displays, scaled to fit inside a drawing area.
///
/// Displays keep their relative positions and sizes, so the result matches the
/// arrangement in System Settings › Displays.
public struct DisplayLayout: Equatable, Sendable {
    /// A display and the rectangle it occupies in the drawing area.
    public struct Item: Identifiable, Equatable, Sendable {
        public let display: Display
        public let rect: CGRect

        public var id: Display.ID { display.id }
    }

    public let items: [Item]

    /// Fits `displays` inside `size`, centred, preserving aspect ratio.
    ///
    /// - Parameters:
    ///   - displays: The displays to lay out, in global screen coordinates.
    ///   - size: The drawing area.
    ///   - spacing: The gap, in drawing-area points, kept between displays that touch.
    public init(displays: [Display], fitting size: CGSize, spacing: CGFloat = 0) {
        guard !displays.isEmpty, size.width > 0, size.height > 0 else {
            items = []
            return
        }

        let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offset = CGPoint(
            x: (size.width - bounds.width * scale) / 2,
            y: (size.height - bounds.height * scale) / 2
        )
        let inset = spacing / 2

        items = displays.map { display in
            let frame = display.frame
            // Global screen coordinates have y pointing up; drawing coordinates point down.
            let rect = CGRect(
                x: offset.x + (frame.minX - bounds.minX) * scale,
                y: offset.y + (bounds.maxY - frame.maxY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
            return Item(display: display, rect: rect.insetBy(dx: inset, dy: inset))
        }
    }
}
