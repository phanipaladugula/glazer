import GlazerCore
import SwiftUI

/// The displays in their real arrangement, drawn like System Settings › Displays, with
/// the focused one highlighted.
struct DisplayMap: View {
    let displays: [Display]

    /// The display in focus, or `nil` when nothing is being followed.
    let focusedID: Display.ID?

    private let mapHeight: CGFloat = 56
    private let labelGap: CGFloat = 5
    private let labelHeight: CGFloat = 13

    var body: some View {
        GeometryReader { proxy in
            let layout = DisplayLayout(
                displays: displays,
                fitting: CGSize(width: proxy.size.width, height: mapHeight),
                spacing: 6
            )
            ZStack(alignment: .topLeading) {
                ForEach(layout.items) { item in
                    DisplayTile(display: item.display, isFocused: item.id == focusedID)
                        .frame(width: item.rect.width, height: item.rect.height)
                        .offset(x: item.rect.minX, y: item.rect.minY)

                    Text(item.display.shortName)
                        .font(.caption2)
                        .foregroundStyle(item.id == focusedID ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(width: item.rect.width + 6)
                        .offset(x: item.rect.minX - 3, y: item.rect.maxY + labelGap)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: mapHeight + labelGap + labelHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Displays")
    }
}

private struct DisplayTile: View {
    let display: Display
    let isFocused: Bool

    private let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)

    var body: some View {
        shape
            .fill(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .overlay(alignment: .top) {
                if display.hasMenuBar {
                    // The menu bar strip, as System Settings draws it on the main display.
                    Rectangle()
                        .fill(.white.opacity(isFocused ? 0.55 : 0.35))
                        .frame(height: 3)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.separator, lineWidth: 0.5)
            }
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .accessibilityElement()
            .accessibilityLabel(display.name)
            .accessibilityValue(isFocused ? "In focus" : "")
    }
}
