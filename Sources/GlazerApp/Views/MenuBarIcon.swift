import SwiftUI

/// The symbol shown in the menu bar. The `eye` symbols share a width, so the menu bar
/// doesn't shift as the camera's state changes. Switching only by key shows a keyboard,
/// so the menu bar never suggests the camera is watching when it isn't.
struct MenuBarIcon: View {
    let condition: AppModel.Condition

    var body: some View {
        let presentation = ConditionPresentation(condition)
        Image(systemName: presentation.symbol)
            .accessibilityLabel("Glazer, \(presentation.status)")
    }
}
