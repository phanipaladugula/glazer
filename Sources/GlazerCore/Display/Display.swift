import CoreGraphics

/// A physical display attached to the Mac.
///
/// This is a plain value so that logic which depends on the display arrangement can be
/// tested without real screens.
public struct Display: Identifiable, Hashable, Sendable {
    /// The Core Graphics display ID. Stable while the display stays connected.
    public let id: CGDirectDisplayID

    /// The name macOS shows for the display, such as "Built-in Retina Display".
    public let name: String

    /// The display's frame in global screen coordinates, in points.
    public let frame: CGRect

    public init(id: CGDirectDisplayID, name: String, frame: CGRect) {
        self.id = id
        self.name = name
        self.frame = frame
    }

    /// Whether this display shows the menu bar. macOS places that display's origin at
    /// (0, 0) in global screen coordinates.
    public var hasMenuBar: Bool {
        frame.origin == .zero
    }

    /// A short name for tight spaces. Every built-in panel is called "Built-in", so
    /// it fits under a small tile; other names are kept as they are.
    public var shortName: String {
        name.hasPrefix("Built-in") ? "Built-in" : name
    }
}
