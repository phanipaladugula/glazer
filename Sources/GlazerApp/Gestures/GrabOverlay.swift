import AppKit
import SwiftUI

/// What the user sees of a grab: a flash on the display taken, and a thumbnail of the
/// screenshot that stays on the display they face until they drop it.
///
/// Neither takes clicks or focus, and Glazer leaves its own windows out of screenshots.
@MainActor
final class GrabOverlay {
    private var thumbnail: NSPanel?
    private var flashWindow: NSWindow?

    private static let thumbnailWidth: CGFloat = 232
    private static let margin: CGFloat = 16

    /// Flashes `frame`, in AppKit screen coordinates, as macOS does for a screenshot.
    func flash(_ frame: CGRect) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        flashWindow?.orderOut(nil)
        let window = Self.overlayWindow(frame: frame)
        window.backgroundColor = .white
        window.alphaValue = 0.5
        window.orderFrontRegardless()
        flashWindow = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                window?.orderOut(nil)
                if self?.flashWindow === window { self?.flashWindow = nil }
            }
        }
    }

    /// Shows `image` in the top right of `visibleFrame`, in AppKit screen coordinates.
    func showThumbnail(_ image: CGImage, on visibleFrame: CGRect) {
        hideThumbnail()
        let host = NSHostingView(rootView: HeldThumbnail(image: image, width: Self.thumbnailWidth))
        let size = host.fittingSize
        let panel = Self.overlayWindow(frame: CGRect(origin: .zero, size: size))
        panel.contentView = host
        panel.setFrameOrigin(Self.origin(for: size, in: visibleFrame))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        thumbnail = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func moveThumbnail(to visibleFrame: CGRect) {
        guard let thumbnail else { return }
        let origin = Self.origin(for: thumbnail.frame.size, in: visibleFrame)
        guard origin != thumbnail.frame.origin else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            thumbnail.animator().setFrameOrigin(origin)
        }
    }

    func hideThumbnail() {
        guard let panel = thumbnail else { return }
        thumbnail = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private static func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.maxY - size.height - margin)
    }

    /// A borderless panel above other windows, on every Space, that ignores the mouse.
    private static func overlayWindow(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

/// The held screenshot, with how to drop it.
private struct HeldThumbnail: View {
    let image: CGImage
    let width: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width - 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            Label("Open your hand to drop it", systemImage: "hand.raised.fingers.spread")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(16)
    }
}
