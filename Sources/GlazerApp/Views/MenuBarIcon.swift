import SwiftUI

/// The symbol shown in the menu bar. `eye` and `eye.slash` share a width, so the menu
/// bar doesn't shift when Glazer is turned on or off.
struct MenuBarIcon: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: isEnabled ? "eye" : "eye.slash")
            .accessibilityLabel(isEnabled ? "Glazer, on" : "Glazer, off")
    }
}
