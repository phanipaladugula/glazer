import SwiftUI

@main
struct GlazerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: model)
        } label: {
            MenuBarIcon(isEnabled: model.isEnabled)
        }
        .menuBarExtraStyle(.window)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The bundled app sets LSUIElement in Info.plist. This covers `swift run`, so
        // Glazer never shows a Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
