import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var launchAtLogin: LaunchAtLoginController
    let onOpenTaskMonitor: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "power",
                title: "Launch at login",
                subtitle: launchAtLogin.statusMessage ?? "Open Codex Pace Bar after signing in"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(
                icon: "bell",
                title: "Usage notifications",
                subtitle: "Warns about high pace or forecast exhaustion; maximum once per day."
            ) {
                Toggle("", isOn: $settings.notificationsEnabled)
                    .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "History-based forecast",
                subtitle: "Forecasts limit usage from the last 30 days."
            ) {
                Toggle("", isOn: $settings.historyBasedForecastEnabled)
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

            SettingsDivider()

            SettingsRow(
                icon: "info.circle",
                title: "App version",
                subtitle: appVersion
            ) {
                Link("GitHub repository", destination: repositoryURL)
            }

            ExperimentalSectionHeader()

            SettingsRow(
                icon: "list.bullet.rectangle",
                title: "Task monitor",
                subtitle: "Local status only. No prompts or token use."
            ) {
                HStack(spacing: 10) {
                    if settings.taskMonitorEnabled {
                        Button("Open") {
                            onOpenTaskMonitor()
                        }
                        .buttonStyle(.bordered)
                    }
                    Toggle("", isOn: $settings.taskMonitorEnabled)
                        .labelsHidden()
                }
            }

            SettingsDivider()

            SettingsRow(
                icon: "rectangle.topthird.inset.filled",
                title: "Task summary in main menu",
                subtitle: settings.taskMonitorEnabled
                    ? "Shows active tasks and ETA in the main menu."
                    : "Enable Task Monitor to use this feature."
            ) {
                Toggle("", isOn: $settings.mainTaskSummaryEnabled)
                    .labelsHidden()
                    .disabled(!settings.taskMonitorEnabled)
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "bell.badge",
                title: "Task notifications",
                subtitle: settings.taskMonitorEnabled
                    ? "Alerts when a task needs approval or input."
                    : "Enable Task Monitor to use this feature."
            ) {
                Toggle("", isOn: $settings.taskNotificationsEnabled)
                    .labelsHidden()
                    .disabled(!settings.taskMonitorEnabled)
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "gauge.with.dots.needle.67percent",
                title: "Work rhythm / Focus Load",
                subtitle: settings.taskMonitorEnabled
                    ? "Describes work continuity and parallel tasks."
                    : "Enable Task Monitor to use this feature."
            ) {
                Toggle("", isOn: $settings.focusLoadEnabled)
                    .labelsHidden()
                    .disabled(!settings.taskMonitorEnabled)
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 620, height: 1000)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.08))
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development build"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/awronski/codex-pace-bar")!
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
        .frame(minHeight: 72)
    }
}

private struct ExperimentalSectionHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(.separator.opacity(0.65))
                    .frame(height: 1)

                Text("EXPERIMENTAL MODE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)

                Rectangle()
                    .fill(.separator.opacity(0.65))
                    .frame(height: 1)
            }

            Text("Optional local tools. Enable only what you need.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 10)
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
