import AppKit

extension NSScreen {
    /// The Core Graphics ID of the display this screen is on.
    public var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
