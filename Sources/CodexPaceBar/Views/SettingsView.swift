import SwiftUI
import CodexPaceBarCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "bell",
                title: "Notify when usage is well above pace",
                subtitle: "Uses 2x the pace delta; maximum once per day."
            ) {
                Toggle("", isOn: $settings.notificationsEnabled)
                    .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(icon: "terminal", title: "Codex executable path") {
                TextField("Codex executable path", text: $settings.codexExecutablePath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            SettingsDivider()

            SettingsRow(
                icon: "arrow.clockwise",
                title: "Refresh interval",
                subtitle: "How often data is refreshed"
            ) {
                Stepper(
                    "\(settings.refreshIntervalSeconds) sec",
                    value: $settings.refreshIntervalSeconds,
                    in: SettingsStore.minimumRefreshInterval...SettingsStore.maximumRefreshInterval,
                    step: 60
                )
                .frame(width: 136)
            }

            SettingsDivider()

            SettingsRow(
                icon: "waveform.path",
                title: "Pace delta",
                subtitle: "Threshold for pace comparison"
            ) {
                Stepper(
                    "\(settings.deltaThresholdPercentagePoints) pp",
                    value: $settings.deltaThresholdPercentagePoints,
                    in: SettingsStore.minimumDeltaThreshold...SettingsStore.maximumDeltaThreshold
                )
                .frame(width: 118)
            }

            SettingsDivider()

            SettingsRow(icon: "paintpalette", title: "Color scheme") {
                Picker("Color scheme", selection: $settings.barColorScheme) {
                    ForEach(BarColorScheme.allCases) { scheme in
                        Text(scheme.settingsTitle).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 282)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 620, height: 420)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.08))
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 18)

            control
                .controlSize(.regular)
        }
        .frame(minHeight: 76)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.55))
            .frame(height: 1)
            .padding(.leading, 52)
    }
}
