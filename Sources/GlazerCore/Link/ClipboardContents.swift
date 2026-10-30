import Foundation

/// What's on the clipboard, as types and their data, for sending to a linked Mac.
public struct ClipboardContents: Codable, Equatable, Sendable {
    /// One copied item, such as a piece of text with plain and rich versions.
    public typealias Item = [String: Data]

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// The most sent between Macs. Larger copies stay on their own Mac.
    public static let maximumSize = 20 * 1024 * 1024

    /// The kinds of data sent: text, rich text, HTML, URLs and images. Files aren't.
    public static let sharedTypes: Set<String> = [
        "public.utf8-plain-text", "public.rtf", "public.html", "public.url", "public.png", "public.tiff",
        "com.apple.flat-rtfd",
    ]

    /// The items with only ``sharedTypes`` kept, and no empty items.
    public var shareable: ClipboardContents {
        ClipboardContents(
            items: items.map { $0.filter { Self.sharedTypes.contains($0.key) } }.filter { !$0.isEmpty })
    }

    public var size: Int {
        items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
    }

    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ClipboardContents {
        try PropertyListDecoder().decode(ClipboardContents.self, from: data)
    }
}
