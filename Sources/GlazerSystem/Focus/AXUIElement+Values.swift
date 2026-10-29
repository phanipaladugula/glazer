import ApplicationServices

/// Typed reads and writes of Accessibility attributes.
extension AXUIElement {
    func value(of attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? {
        value(of: attribute) as? String
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(of: attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The type ID was checked above, so this downcast is safe.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    var processID: pid_t? {
        var processID: pid_t = 0
        return AXUIElementGetPid(self, &processID) == .success ? processID : nil
    }

    /// The element's frame in Core Graphics global coordinates.
    var frame: CGRect? {
        guard let positionValue = axValue(kAXPositionAttribute), let sizeValue = axValue(kAXSizeAttribute) else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// Moves and resizes the element, such as a window, and returns whether both took.
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return false
        }
        // Size first: a window too big for where it's going may be pushed back on screen.
        let sized = AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, originValue)
        return sized == .success && moved == .success
    }

    private func axValue(_ attribute: String) -> AXValue? {
        guard let value = value(of: attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // The type ID was checked above, so this downcast is safe.
        return unsafeDowncast(value, to: AXValue.self)
    }
}
