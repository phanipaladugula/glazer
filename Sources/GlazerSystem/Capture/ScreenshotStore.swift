import AppKit
import UniformTypeIdentifiers

/// Saves screenshots where macOS saves its own, and puts them on the clipboard.
public enum ScreenshotStore {
    /// The folder macOS saves screenshots to: the one chosen in the Screenshot app's
    /// Options, or the Desktop.
    public static var folder: URL {
        let desktop =
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Desktop")
        guard let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            !location.isEmpty
        else { return desktop }
        let folder = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return desktop }
        return folder
    }

    /// The file name for a screenshot taken at `date`, in the style macOS uses, so
    /// Glazer's screenshots sort among the user's own.
    public static func fileName(for date: Date, attempt: Int = 1) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let suffix = attempt > 1 ? " (\(attempt))" : ""
        return "Screenshot \(formatter.string(from: date))\(suffix).png"
    }

    /// Saves `png` in `folder`, never replacing a file, and returns where.
    public static func save(png data: Data, at date: Date = .now, in folder: URL = folder) throws -> URL {
        for attempt in 1...100 {
            let url = folder.appending(path: fileName(for: date, attempt: attempt))
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Puts `image` on the clipboard as a PNG, and as TIFF for older apps.
    @MainActor
    public static func copy(_ image: CGImage, png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// `image` as PNG data.
    public static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
