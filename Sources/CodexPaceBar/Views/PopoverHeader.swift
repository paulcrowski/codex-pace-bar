import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct PopoverHeader: View {
    let model: AppModel
    let settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: largeBarImage)
                .frame(width: 425, height: 54)
                .accessibilityLabel(model.displayState.statusTitle)

            if model.isRefreshing {
                Text("Refreshing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var largeBarImage: NSImage {
        MenuBarIconRenderer(size: NSSize(width: 425, height: 54)).render(
            snapshot: model.snapshot,
            state: model.displayState,
            isStale: model.snapshot?.isStale ?? false,
            colorScheme: settings.barColorScheme
        )
    }
}
