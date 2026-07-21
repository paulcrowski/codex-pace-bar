@preconcurrency import AppKit
import CodexPaceBarAppSupport
import CodexPaceBarCore
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var launchAtLogin: LaunchAtLoginController
    let onOpenTaskMonitor: () -> Void
    let onGetTaskHookStatus: () -> CodexHookSetupStatus
    @State private var showsHookSetup = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
            SettingsRow(
                icon: "power",
                title: "Launch at login",
                subtitle: launchAtLogin.statusMessage ?? "Open Codex Pace Bar after signing in"
            ) {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
            }

            SettingsDivider()

            SettingsRow(
                icon: "bell",
                title: "Usage notifications",
                subtitle: "Warns about high pace or forecast exhaustion; maximum once per day."
            ) {
                Toggle("Usage notifications", isOn: $settings.notificationsEnabled)
            }

            SettingsDivider()

            SettingsRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "History-based forecast",
                subtitle: "Forecasts limit usage from the last 30 days."
            ) {
                Toggle("History-based forecast", isOn: $settings.historyBasedForecastEnabled)
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
                    Toggle("Task monitor", isOn: $settings.taskMonitorEnabled)
                }
            }

            SettingsDivider()

            SettingsRow(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Live Codex hooks · Optional",
                subtitle: settings.taskMonitorEnabled
                    ? hookStatusSummary(onGetTaskHookStatus())
                    : "Enable Task Monitor to install the local hooks."
            ) {
                Button("Setup") { showsHookSetup = true }
                    .buttonStyle(.bordered)
                    .disabled(!settings.taskMonitorEnabled)
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "rectangle.topthird.inset.filled",
                title: "Task summary in main menu",
                subtitle: settings.taskMonitorEnabled
                    ? "Shows active tasks and ETA in the main menu."
                    : "Enable Task Monitor to use this feature."
            ) {
                Toggle("Task summary in main menu", isOn: $settings.mainTaskSummaryEnabled)
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
                Toggle("Work rhythm and Focus Load", isOn: $settings.focusLoadEnabled)
                    .disabled(!settings.taskMonitorEnabled)
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.visible)
        .frame(minWidth: 420, idealWidth: 620, minHeight: 520, idealHeight: 760)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.08))
        }
        .sheet(isPresented: $showsHookSetup) {
            CodexHookSetupView(loadStatus: onGetTaskHookStatus)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development build"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/awronski/codex-pace-bar")!
    }

    private func hookStatusSummary(_ status: CodexHookSetupStatus) -> String {
        if status.hasObservedAllRequiredHooks {
            return "Working. All three Codex event types have been seen."
        }
        if status.isReceivingEvents {
            let count = status.observedHookNames.intersection(CodexHookInstaller.requiredHookNames).count
            return "Installed. \(count)/3 event types have been seen in use."
        }
        if status.isConfigured {
            return "Installed. Each event will show as Working after its first use."
        }
        return "Not installed. Toggle Task Monitor off and on to retry."
    }
}

private struct CodexHookSetupView: View {
    let loadStatus: () -> CodexHookSetupStatus
    @Environment(\.dismiss) private var dismiss
    @State private var status: CodexHookSetupStatus = .notConfigured
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Improve live Codex status")
                        .font(.system(size: 20, weight: .semibold))
                    Text(statusTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Task Monitor reads local Codex session logs. Hooks add immediate prompt, permission, and stop updates.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Codex Pace Bar installs these three hooks automatically when you enable Task Monitor. You only review and enable them in Codex.")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Text("Codex shows whether a hook is trusted and enabled. Pace Bar shows Installed when it finds the hook, and Working after that event actually happens. PermissionRequest stays Installed until Codex really asks for approval.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                Text("WHAT EACH HOOK ADDS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                hookStatusRow(
                    "PermissionRequest",
                    purpose: "Shows Needs you when Codex asks for approval."
                )
                Divider()
                hookStatusRow(
                    "UserPromptSubmit",
                    purpose: "Marks a new request as started immediately."
                )
                Divider()
                hookStatusRow(
                    "Stop",
                    purpose: "Marks the current Codex turn as finished immediately."
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                setupStep("1", "In Codex, open Settings → Hooks → User config.")
                setupStep("2", "For the three hooks installed by Codex Pace Bar, click Trust and turn on the switch.")
                setupStep("3", "Start a new task, then return here and refresh the status.")
            }

            Text("A pasted prompt cannot approve hooks. Codex requires this manual review because hooks can run outside its sandbox.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(didCopy ? "Steps copied" : "Copy setup steps") {
                    copySetupSteps()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh status") {
                    status = loadStatus()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text("Privacy: the forwarder keeps task identifiers, project folder, model, navigation metadata, and status. Prompt and response text are discarded.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 510)
        .onAppear { status = loadStatus() }
    }

    private var statusTitle: String {
        if status.hasObservedAllRequiredHooks { return "Working · all 3 event types seen" }
        if status.isReceivingEvents { return "Installed · live events are arriving" }
        if status.isConfigured { return "Installed · ready for first use" }
        return "Hooks are not installed"
    }

    private var statusColor: Color {
        if status.isReceivingEvents { return .green }
        if status.isConfigured { return .secondary }
        return .orange
    }

    private func setupStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hookStatusRow(_ eventName: String, purpose: String) -> some View {
        let displayState = status.displayState(for: eventName)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: hookIcon(for: displayState))
                .foregroundStyle(displayState == .working ? .green : .secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(eventName)
                    .font(.system(size: 12, weight: .semibold))
                Text(purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(hookLabel(for: displayState))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(displayState == .working ? .green : .secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }

    private func hookIcon(for state: CodexHookDisplayState) -> String {
        switch state {
        case .working: "checkmark.circle.fill"
        case .installed: "checkmark.circle"
        case .notInstalled: "xmark.circle"
        }
    }

    private func hookLabel(for state: CodexHookDisplayState) -> String {
        switch state {
        case .working: "Working"
        case .installed: "Installed"
        case .notInstalled: "Not installed"
        }
    }

    private func copySetupSteps() {
        let steps = """
        Enable Task Monitor in Codex Pace Bar. It installs PermissionRequest, UserPromptSubmit, and Stop automatically.
        In Codex, open Settings → Hooks → User config, then trust and enable those three hooks.
        Start a new Codex task, then refresh the hook status in Codex Pace Bar.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(steps, forType: .string)
        didCopy = true
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
