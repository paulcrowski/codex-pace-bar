import SwiftUI
import CodexPaceBarCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                TextField("Codex executable path", text: $settings.codexExecutablePath)
                    .textFieldStyle(.roundedBorder)

                Stepper(
                    "Refresh interval: \(settings.refreshIntervalSeconds) seconds",
                    value: $settings.refreshIntervalSeconds,
                    in: SettingsStore.minimumRefreshInterval...SettingsStore.maximumRefreshInterval,
                    step: 60
                )

                Stepper(
                    "Pace delta: \(settings.deltaThresholdPercentagePoints) pp",
                    value: $settings.deltaThresholdPercentagePoints,
                    in: SettingsStore.minimumDeltaThreshold...SettingsStore.maximumDeltaThreshold
                )

                Picker("Color scheme", selection: $settings.barColorScheme) {
                    ForEach(BarColorScheme.allCases) { scheme in
                        Text(scheme.settingsTitle).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(20)
        .frame(width: 460, height: 280)
    }
}
