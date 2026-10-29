import SwiftUI

/// Marks a feature that works but isn't reliable enough yet to depend on.
struct ExperimentalBadge: View {
    var body: some View {
        Text("Experimental")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Experimental feature")
    }
}
