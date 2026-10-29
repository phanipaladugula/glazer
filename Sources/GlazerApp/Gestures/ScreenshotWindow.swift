import AppKit
import GlazerCore
import SwiftUI

/// Shows a dropped screenshot in a window of Glazer's own, in the middle of the display
/// it was dropped on.
///
/// Glazer's own window rather than Preview's, because only then is the place certain:
/// Preview puts a window back where it last had one, which can be another display, or
/// one that's no longer connected, and moving another app's window needs it to be found
/// first.
@MainActor
final class ScreenshotWindows {
    private var windows: [NSWindow] = []

    func show(_ image: CGImage, file: URL, on screen: NSScreen) {
        let imageSize = CGSize(
            width: CGFloat(image.width) / screen.backingScaleFactor,
            height: CGFloat(image.height) / screen.backingScaleFactor)
        let barHeight: CGFloat = 52
        let content = Placement.centred(
            CGSize(width: imageSize.width, height: imageSize.height + barHeight), in: screen.visibleFrame,
            within: 0.75)

        let window = NSWindow(
            contentRect: content, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
            defer: false)
        window.title = file.deletingPathExtension().lastPathComponent
        window.representedURL = file
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.contentView = NSHostingView(
            rootView: ScreenshotView(image: image, file: file) { [weak window] in window?.close() })
        // The frame for the content, set again now the title bar exists, then centred.
        window.setFrame(
            Placement.centred(window.frameRect(forContentRect: content).size, in: screen.visibleFrame), display: false)

        let id = ObjectIdentifier(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows.removeAll { ObjectIdentifier($0) == id }
            }
        }
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// The screenshot, with ways to keep working on it.
private struct ScreenshotView: View {
    let image: CGImage
    let file: URL
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.04))
            Divider()
            HStack(spacing: 8) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                Button("Open in Preview") {
                    NSWorkspace.shared.open(file)
                    close()
                }
                Spacer()
                Text("Copied to the clipboard")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
        }
        .onExitCommand(perform: close)
    }
}
