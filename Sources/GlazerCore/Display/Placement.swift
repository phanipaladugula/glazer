import CoreGraphics

/// Where to put a window on a display.
public enum Placement {
    /// A frame for content of `size` centred in `area`, shrunk to fit within `fraction` of
    /// it if it's bigger, keeping its shape. Edges are rounded to whole points.
    public static func centred(_ size: CGSize, in area: CGRect, within fraction: Double = 0.9) -> CGRect {
        let limit = CGSize(width: area.width * fraction, height: area.height * fraction)
        let scale = min(1, limit.width / max(size.width, 1), limit.height / max(size.height, 1))
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return CGRect(
            x: (area.midX - fitted.width / 2).rounded(),
            y: (area.midY - fitted.height / 2).rounded(),
            width: fitted.width,
            height: fitted.height)
    }
}
