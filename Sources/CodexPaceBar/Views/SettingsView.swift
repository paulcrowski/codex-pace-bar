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
    let onSendMobileNotificationTest: () async -> Bool
    @State private var showsMobilePairing = false
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

            SettingsRow(
                icon: "chart.bar.xaxis",
                title: "Personalized task estimates",
                subtitle: "Uses your local plan history to estimate total time and when it is safe to step away."
            ) {
                Toggle("Personalized task estimates", isOn: $settings.planAwareEstimatesEnabled)
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
                icon: "iphone",
                title: "Phone notifications · Experimental",
                subtitle: settings.taskMonitorEnabled
                    ? "Sends private task-ready alerts through ntfy to iOS or Android."
                    : "Enable Task Monitor to use this feature."
            ) {
                HStack(spacing: 10) {
                    if settings.mobileTaskNotificationsEnabled {
                        Button("Pair") { showsMobilePairing = true }
                            .buttonStyle(.bordered)
                    }
                    Toggle(
                        "Phone notifications",
                        isOn: Binding(
                            get: { settings.mobileTaskNotificationsEnabled },
                            set: { enabled in
                                settings.mobileTaskNotificationsEnabled = enabled
                                if enabled { showsMobilePairing = true }
                            }
                        )
                    )
                        .disabled(!settings.taskMonitorEnabled)
                }
            }
            .opacity(settings.taskMonitorEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "text.bubble",
                title: "Phone notification details",
                subtitle: settings.mobileTaskNotificationsEnabled
                    ? "Includes project name and duration. Prompts always stay private."
                    : "Enable Phone notifications to add safe task context."
            ) {
                Toggle("Phone notification details", isOn: $settings.mobileNotificationDetailsEnabled)
                    .disabled(!settings.taskMonitorEnabled || !settings.mobileTaskNotificationsEnabled)
            }
            .opacity(settings.taskMonitorEnabled && settings.mobileTaskNotificationsEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "moon.stars",
                title: "Swarms / Goals Silent",
                subtitle: settings.mobileTaskNotificationsEnabled
                    ? "One alert when a detected goal or swarm ends. Needs you stays instant."
                    : "Enable Phone notifications to silence goal and swarm completion noise."
            ) {
                Toggle("Swarms and goals silent", isOn: $settings.silentGoalsAndSwarmsEnabled)
                    .disabled(!settings.taskMonitorEnabled || !settings.mobileTaskNotificationsEnabled)
            }
            .opacity(settings.taskMonitorEnabled && settings.mobileTaskNotificationsEnabled ? 1 : 0.55)

            SettingsDivider()

            SettingsRow(
                icon: "bell.badge",
                title: "Task notifications",
                subtitle: settings.taskMonitorEnabled
                    ? "Alerts when a task needs approval or input."
                    : "Enable Task Monitor to use this feature."
            ) {
                Toggle("Task notifications", isOn: $settings.taskNotificationsEnabled)
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
        .sheet(isPresented: $showsMobilePairing) {
            MobileNotificationPairingView(
                settings: settings,
                onSendTest: onSendMobileNotificationTest
            )
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

            Text("Task Monitor and task-finished phone alerts still work from local Codex session logs. Hooks add immediate prompt, permission, and stop updates.")
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

private struct MobileNotificationPairingView: View {
    @Bindable var settings: SettingsStore
    let onSendTest: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var testState = TestState.idle

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone notifications")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Experimental · powered by ntfy")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(alignment: .center, spacing: 20) {
                VStack(spacing: 7) {
                    Label("Android · scan QR", systemImage: "qrcode")
                        .font(.system(size: 12, weight: .semibold))
                    if let image = androidQRCodeImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 170, height: 170)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Opens the native ntfy app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 220)

                VStack(spacing: 12) {
                    Label("iPhone · add topic", systemImage: "apple.logo")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "iphone")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(.blue)
                    Text("Open ntfy, tap +, then paste the private topic shown below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Get the iPhone app", destination: URL(string: "https://apps.apple.com/app/ntfy/id1625396347")!)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("The ntfy mobile app is required", systemImage: "iphone.gen3")
                    .font(.system(size: 12, weight: .semibold))
                Text("The page opened in Chrome is only a web viewer. It will not reliably notify you when the phone is asleep.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                pairingStep("1", "Install and open the native ntfy app on your phone.")
                pairingStep("2", "Android: scan the QR and choose ntfy. If Chrome opens, copy the topic and add it with + inside the ntfy app.")
                pairingStep("3", "iPhone: open ntfy, tap +, then paste the private topic below.")
                pairingStep("4", "Android: in ntfy open Codex Pace Bar → Settings → enable Instant delivery, then allow the requested Android permission. iPhone: allow ntfy notifications when asked.")
                pairingStep("5", "Send a test, lock the phone for 2 minutes, then send another test. Both should arrive before you unlock it.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("If the second test arrives only after unlocking, Android is delaying ntfy. In ntfy enable Settings → Record logs and check that instant delivery stays active.")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(settings.mobileNotificationTopic)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") { copyTopic() }
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Link("Android app", destination: URL(string: "https://play.google.com/store/apps/details?id=io.heckel.ntfy")!)
                Link("iPhone app", destination: URL(string: "https://apps.apple.com/app/ntfy/id1625396347")!)
                Button("New pairing code") {
                    settings.regenerateMobileNotificationTopic()
                    testState = .idle
                }
                Spacer()
                testButton
            }

            Text("Treat the topic like a password: create a new pairing code if it was shared or shown in a screenshot. Only generic task status is sent by default. If you enable Phone notification details, the project name and duration are also sent; prompts, responses, code, and full paths stay on this Mac. The public ntfy relay handles the notification text and private topic.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private var testButton: some View {
        switch testState {
        case .idle:
            Button("Send test") { sendTest() }
                .buttonStyle(.borderedProminent)
        case .sending:
            ProgressView()
                .controlSize(.small)
                .frame(width: 80)
        case .sent:
            Label("Test sent", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Button("Try again") { sendTest() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    private func pairingStep(_ number: String, _ text: String) -> some View {
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

    private var androidQRCodeImage: NSImage? {
        guard let url = MobileTaskNotificationService.androidSubscriptionURL(
            topic: settings.mobileNotificationTopic
        ) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    private func copyTopic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.mobileNotificationTopic, forType: .string)
    }

    private func sendTest() {
        testState = .sending
        Task { @MainActor in
            testState = await onSendTest() ? .sent : .failed
        }
    }

    private enum TestState {
        case idle
        case sending
        case sent
        case failed
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
