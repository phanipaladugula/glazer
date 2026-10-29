import GlazerCore
import SwiftUI

/// The displays in their real arrangement, drawn like System Settings › Displays, with
/// the focused one highlighted. Each name is drawn inside its own display, so it can't
/// land on a neighbour, such as a display stacked below.
struct DisplayMap: View {
    let displays: [Display]

    /// The display in focus, or `nil` when nothing is being followed.
    let focusedID: Display.ID?

    private let mapHeight: CGFloat = 76

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
                }
            }
        }
        .frame(height: mapHeight)
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
            .overlay {
                Text(display.shortName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
            }
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .accessibilityElement()
            .accessibilityLabel(display.name)
            .accessibilityValue(isFocused ? "In focus" : "")
    }
}
