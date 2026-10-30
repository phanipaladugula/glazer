import AppKit
import GlazerCore

/// Reads and writes the clipboard as ``ClipboardContents``, for sending to a linked Mac.
@MainActor
public enum ClipboardBridge {
    /// Counts every change to the clipboard, by any app.
    public static func changeCount(of pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.changeCount
    }

    /// The clipboard's shareable contents, or `nil` if there's nothing to share or it's
    /// larger than ``ClipboardContents/maximumSize``.
    public static func read(from pasteboard: NSPasteboard = .general) -> ClipboardContents? {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type -> (String, Data)? in
                    guard ClipboardContents.sharedTypes.contains(type.rawValue), let data = item.data(forType: type)
                    else { return nil }
                    return (type.rawValue, data)
                })
        }
        let contents = ClipboardContents(items: items).shareable
        guard !contents.items.isEmpty, contents.size <= ClipboardContents.maximumSize else { return nil }
        return contents
    }

    /// Replaces the clipboard with `contents`, and returns the new change count.
    @discardableResult
    public static func write(_ contents: ClipboardContents, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        let items = contents.items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
        return pasteboard.changeCount
    }
}
