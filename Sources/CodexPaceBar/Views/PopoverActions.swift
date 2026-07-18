import SwiftUI

struct PopoverActions: View {
    let needsCodexSetup: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onChooseCodexPath: () -> Void

    var body: some View {
        if needsCodexSetup {
            setupActions
        } else {
            normalActions
        }
    }

    private var normalActions: some View {
        VStack(spacing: 16) {
            Divider()

            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onQuit) {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
    }

    private var setupActions: some View {
        VStack(spacing: 16) {
            Divider()

            HStack(spacing: 14) {
                Button(action: onChooseCodexPath) {
                    Label("Choose codex path", systemImage: "folder.badge.questionmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
    }
}
