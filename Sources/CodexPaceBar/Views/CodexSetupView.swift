import AppKit
import CodexPaceBarAppSupport
import SwiftUI

struct CodexSetupView: View {
    let settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex CLI needs setup")
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)

            Text("Codex Pace Bar needs a working `codex` command to read your weekly limit.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openCodexSetupGuide) {
                Label("Codex setup guide", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
        .padding(.top, 112)
        .padding(.bottom, 22)
    }

    private func openCodexSetupGuide() {
        guard let url = URL(string: "https://developers.openai.com/codex/cli") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
