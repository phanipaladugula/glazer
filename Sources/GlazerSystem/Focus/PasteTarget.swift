import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Finds whether the pointer is over somewhere that takes a paste, such as a message box
/// or a document, and pastes there.
///
/// Both need Accessibility access, which Glazer already has to move keyboard focus.
@MainActor
public enum PasteTarget {
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Apps already asked to describe their content.
    private static var askedProcesses: Set<pid_t> = []

    /// Chromium-based browsers, which describe web pages to Accessibility only once an
    /// assistive app turns on their enhanced interface.
    private static let chromiumBrowsers = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium", "com.openai.atlas",
    ]

    /// What's under `point`, in Core Graphics global coordinates, if it takes typing, so a
    /// paste there lands in it: a short description such as "AXTextArea in Notes", or
    /// `nil`. Password fields never count.
    public static func find(at point: CGPoint) async -> String? {
        guard AccessibilityAccess.isGranted, let element = element(at: point) else { return nil }
        if let found = editable(element) {
            return describe(found)
        }
        guard askToDescribeContent(of: element) else { return nil }
        // Chromium and Electron apps, such as Chrome, Slack and VS Code, take a moment to
        // build the description of their content once asked. Look again a few times.
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(150))
            if let element = self.element(at: point), let found = editable(element) {
                return describe(found)
            }
        }
        return nil
    }

    /// Pastes the clipboard at `point`: brings its window forward, clicks there so the
    /// caret lands where the user pointed, then presses ⌘V.
    public static func paste(at point: CGPoint) async {
        if let element = element(at: point) {
            bringForward(element)
            try? await Task.sleep(for: .milliseconds(150))
        }
        click(at: point)
        try? await Task.sleep(for: .milliseconds(120))
        pressCommand(character: "v", fallback: CGKeyCode(kVK_ANSI_V))
    }

    // MARK: Finding the target

    private static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        return result == .success ? element : nil
    }

    /// Asks the app that owns `element` to describe its content to Accessibility, once
    /// per app. Returns whether it was asked now.
    private static func askToDescribeContent(of element: AXUIElement) -> Bool {
        guard let processID = element.processID, !askedProcesses.contains(processID) else { return false }
        askedProcesses.insert(processID)
        let application = AXUIElementCreateApplication(processID)
        // Electron apps.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Chromium browsers. Only them: in other apps it can slow window animations.
        let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier ?? ""
        if chromiumBrowsers.contains(where: bundleID.hasPrefix) {
            AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        return true
    }

    /// `element`, or the control it's part of, if it takes typing.
    static func editable(_ element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        // A few levels up is enough: the pointer is usually over a field's text, a line of
        // it, or a placeholder inside it.
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            if candidate.string(kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return nil }
            let role = candidate.string(kAXRoleAttribute)
            if let role, textRoles.contains(role) {
                return (candidate.value(of: kAXEnabledAttribute) as? Bool) != false ? candidate : nil
            }
            // Web content: Safari and Chromium mark everything inside an editable area,
            // such as a contenteditable message box, with its editable ancestor.
            if let ancestor = candidate.element("AXEditableAncestor") { return ancestor }
            if role == kAXWindowRole || role == "AXWebArea" || role == kAXApplicationRole { return nil }
            current = candidate.element(kAXParentAttribute)
        }
        return nil
    }

    private static func describe(_ element: AXUIElement) -> String {
        let role = element.string(kAXRoleAttribute) ?? "element"
        let app = element.processID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "an app"
        return "\(role) in \(app)"
    }

    // MARK: Pasting

    private static func bringForward(_ element: AXUIElement) {
        if let window = element.element(kAXWindowAttribute) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if let processID = element.processID {
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Presses ⌘ and the key that types `character` in the current keyboard layout, so
    /// ⌘V is ⌘V on AZERTY and Dvorak too.
    private static func pressCommand(character: Character, fallback: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let code = KeyboardLayout.keyCode(typing: character) ?? fallback
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// The current keyboard layout.
enum KeyboardLayout {
    /// The key code that types `character` with no modifiers, or `nil` if no key does.
    static func keyCode(typing character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let target = String(character)

        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                if status == noErr, length == 1, String(utf16CodeUnits: characters, count: 1) == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
