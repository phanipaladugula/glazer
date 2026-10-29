import AppKit
import Carbon.HIToolbox
import GlazerCore
import Security
import Testing

@testable import GlazerSystem

/// Whether this machine's login keychain accepts new items without asking. CI runners and
/// developer Macs do; a locked or headless keychain doesn't, and the tests skip there.
private let keychainAvailable: Bool = {
    let probe: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.phanipaladugula.glazer.tests.probe-\(UUID())",
        kSecAttrAccount as String: "probe",
        kSecValueData as String: Data([1]),
    ]
    guard SecItemAdd(probe as CFDictionary, nil) == errSecSuccess else { return false }
    SecItemDelete(probe as CFDictionary)
    return true
}()

@Suite("FaceVault, against the real Keychain", .enabled(if: keychainAvailable, "the keychain isn't available"))
struct FaceVaultTests {
    /// A vault in its own service, so tests never touch a real face lock item.
    let vault = FaceVault(service: "io.github.phanipaladugula.glazer.tests-\(UUID())")
    let template = FaceTemplate(signatures: [FaceSignature(values: [1, 0, 0]), FaceSignature(values: [0.9, 0.1, 0])])

    @Test("A new vault is empty")
    func empty() throws {
        #expect(try vault.load() == nil)
        #expect(!vault.hasTemplate)
    }

    @Test("A template survives a round trip, and updates in place")
    func roundTrip() throws {
        defer { try? vault.delete() }
        try vault.save(template)
        #expect(vault.hasTemplate)
        #expect(try vault.load() == template)

        let replacement = FaceTemplate(signatures: [FaceSignature(values: [0, 1, 0])])
        try vault.save(replacement)
        #expect(try vault.load() == replacement)
    }

    @Test("Deleting removes the template, and deleting again is harmless")
    func delete() throws {
        try vault.save(template)
        try vault.delete()
        #expect(try vault.load() == nil)
        try vault.delete()
    }
}

@Suite("Displays and windows")
@MainActor
struct DisplayAndWindowTests {
    @Test("Every connected screen becomes a display, one of them with the menu bar")
    func displays() {
        let displays = NSScreen.screens.compactMap(Display.init(screen:))
        #expect(displays.count == NSScreen.screens.count)
        if !displays.isEmpty {
            #expect(displays.contains { $0.hasMenuBar })
        }
    }

    @Test("No window is found on a display that doesn't exist")
    func noWindowOffscreen() {
        #expect(FocusController.frontmostWindow(on: CGRect(x: 100_000, y: 100_000, width: 100, height: 100)) == nil)
    }

    @Test("A found window is centred on the display it was looked for on")
    func windowOnDisplay() {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        if let window = FocusController.frontmostWindow(on: bounds) {
            #expect(bounds.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY)))
            #expect(window.processID != ProcessInfo.processInfo.processIdentifier)
        }
    }
}

@Suite("Keyboard")
@MainActor
struct KeyboardTests {
    @Test("A global shortcut registers and unregisters")
    func hotKey() throws {
        _ = NSApplication.shared
        var hotKey: HotKey? = try HotKey(KeyboardShortcut(key: "J", modifiers: [.control, .option, .shift, .command])) {
        }
        #expect(hotKey != nil)
        hotKey = nil
        // The same shortcut can be registered again once released.
        let again = try HotKey(KeyboardShortcut(key: "J", modifiers: [.control, .option, .shift, .command])) {}
        _ = again
    }

    @Test("A key without a key code is rejected")
    func unsupportedKey() {
        #expect(throws: HotKey.Error.self) {
            _ = try HotKey(KeyboardShortcut(key: "é", modifiers: [.command])) {}
        }
    }

    @Test("Secure input reports no owner when it's off")
    func secureInput() {
        let monitor = TypingMonitor()
        if !IsSecureEventInputEnabled() {
            #expect(monitor.secureInputOwner == nil)
        }
    }
}
