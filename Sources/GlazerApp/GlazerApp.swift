import GlazerCore
import SwiftUI

@main
struct GlazerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: model)
        } label: {
            MenuBarIcon(condition: model.condition)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Glazer", id: WindowID.setup) {
            SetupView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(Preferences().hasCompletedSetup ? .suppressed : .presented)

        Window("Face Lock", id: WindowID.faceLock) {
            FaceLockSetupView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
        }
    }
}

enum WindowID {
    static let setup = "setup"
    static let faceLock = "face-lock"
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The bundled app sets LSUIElement in Info.plist. This covers `swift run`, so
        // Glazer never shows a Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
