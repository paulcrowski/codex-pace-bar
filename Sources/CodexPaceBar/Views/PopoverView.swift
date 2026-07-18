import AppKit
import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    let settings: SettingsStore
    let history: UsageHistoryStore
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(model: model, settings: settings)

            if model.failure?.requiresCodexSetup == true {
                CodexSetupView(settings: settings)
            } else if let failure = model.failure {
                Text("Could not read Codex weekly limit.")
                    .font(.headline)
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let snapshot = model.snapshot {
                ScrollView(.vertical, showsIndicators: false) {
                    PopoverMetricsSection(model: model, history: history, snapshot: snapshot)
                }
            } else {
                Text("Reading Codex rate limits...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }

            PopoverActions(
                needsCodexSetup: model.failure?.requiresCodexSetup == true,
                isRefreshing: model.isRefreshing,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit,
                onChooseCodexPath: { settings.chooseCodexPath() }
            )
        }
        .padding(20)
        .frame(width: 465, height: 650)
    }
}

private extension SettingsStore {
    func chooseCodexPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose codex executable"
        panel.prompt = "Choose"
        panel.message = "Select the codex command-line executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if FileManager.default.isExecutableFile(atPath: url.path) {
            codexExecutablePath = url.path
        } else {
            let alert = NSAlert()
            alert.messageText = "Selected file is not executable."
            alert.informativeText = "Choose the real codex command file."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
