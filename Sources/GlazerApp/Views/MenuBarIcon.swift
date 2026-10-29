import SwiftUI

/// The symbol shown in the menu bar. The `eye` symbols share a width, so the menu bar
/// doesn't shift when the state changes.
struct MenuBarIcon: View {
    let condition: AppModel.Condition

    var body: some View {
        let presentation = ConditionPresentation(condition)
        Image(systemName: presentation.symbol)
            .accessibilityLabel("Glazer, \(presentation.status)")
    }
}
