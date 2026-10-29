import SwiftUI

/// A row that looks and behaves like an `NSMenu` item: full width, highlighted on hover,
/// with an optional shortcut on the trailing edge.
struct MenuRow: View {
    private let title: String
    private let shortcut: String?
    private let action: () -> Void

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HighlightingLabel(configuration: configuration)
    }

    private struct HighlightingLabel: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let isHighlighted = isHovered && isEnabled
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                }
                .onHover { isHovered = $0 }
        }
    }
}
