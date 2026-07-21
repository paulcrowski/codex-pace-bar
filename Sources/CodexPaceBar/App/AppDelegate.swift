@preconcurrency import AppKit
import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let history = UsageHistoryStore()
    private let launchAtLogin = LaunchAtLoginController()
    private lazy var model = AppModel()
    private let notificationController = PaceNotificationController()
    private let taskNotificationController = TaskMonitorNotificationController()
    private let hookInstaller = CodexHookInstaller()
    private let uiProofMode = ProcessInfo.processInfo.arguments.contains("--ui-proof")
    private var uiProofDirectory: URL?
    private lazy var coordinator = RefreshCoordinator(
        model: model,
        settings: settings,
        history: history,
        notificationHandler: { [weak self] snapshot, forecast, now in
            guard let self else {
                return
            }
            self.notificationController.notifyIfNeeded(
                snapshot: snapshot,
                forecast: forecast,
                enabled: self.settings.notificationsEnabled,
                deltaThresholdPercentagePoints: self.settings.deltaThresholdPercentagePoints,
                now: now
            )
        }
    )
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var taskMonitorCoordinator: TaskMonitorCoordinator?
    private var taskMonitorViewModel: TaskMonitorViewModel?
    private var taskMonitorStatusBarController: TaskMonitorStatusBarController?
    private var deferredTaskMonitorStart: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var markerTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(
            settings: settings,
            launchAtLogin: launchAtLogin,
            onOpenTaskMonitor: { [weak self] in self?.showTaskMonitor() },
            onGetTaskHookStatus: { [weak self] in
                self?.taskHookSetupStatus() ?? .notConfigured
            },
            onSendMobileNotificationTest: { [weak self] in
                guard let self else { return false }
                return await self.taskNotificationController.sendMobileTest(
                    topic: self.settings.mobileNotificationTopic
                )
            }
        )
        statusBarController = StatusBarController(
            model: model,
            settings: settings,
            history: history,
            onRefresh: { [weak self] in self?.coordinator.requestRefresh() },
            onOpenSettings: { [weak self] in self?.settingsWindowController?.show() },
            onOpenTaskMonitor: { [weak self] in self?.showTaskMonitor() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        settings.onChange = { [weak self] change in
            self?.settingsDidChange(change)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        scheduleTimers()
        if settings.taskMonitorEnabled {
            if !uiProofMode {
                do {
                    try installTaskHooks()
                } catch {
                    NSLog("Codex Pace Bar could not install local task hooks: \(error.localizedDescription)")
                }
            }
        }
        coordinator.requestRefresh()
        startTaskMonitorAfterCoreRefreshIfNeeded()

        if ProcessInfo.processInfo.arguments.contains("--show-task-monitor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showTaskMonitor()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusBarController?.show()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsWindowController?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        markerTimer?.invalidate()
        deferredTaskMonitorStart?.cancel()
        taskMonitorCoordinator?.stop()
        taskMonitorStatusBarController?.stop()
        taskMonitorStatusBarController = nil
        Task { await coordinator.shutdown() }
        if uiProofMode {
            if let uiProofDirectory {
                try? FileManager.default.removeItem(at: uiProofDirectory)
            }
        }
    }

    private func settingsDidChange(_ change: SettingsStore.Change) {
        switch change {
        case .refreshInterval:
            scheduleTimers()
        case .taskMonitor:
            if settings.taskMonitorEnabled {
                do {
                    try installTaskHooks()
                } catch {
                    NSLog("Codex Pace Bar could not install local task hooks: \(error.localizedDescription)")
                }
                reconcileTaskMonitorRuntime()
            } else {
                stopTaskMonitor()
                try? hookInstaller.uninstall()
            }
        case .mainTaskSummary:
            reconcileTaskMonitorRuntime()
        case .focusLoad:
            taskMonitorViewModel?.focusLoadEnabled = settings.focusLoadEnabled
        case .forecastMode:
            taskMonitorViewModel?.planAwareEstimatesEnabled = settings.planAwareEstimatesEnabled
            taskMonitorViewModel?.reload()
        case .display:
            statusBarController?.refreshIcon()
        case .taskNotifications:
            reconcileTaskMonitorRuntime()
        case .mobileTaskNotifications:
            taskNotificationController.resetMobileBaseline()
            reconcileTaskMonitorRuntime()
            taskMonitorViewModel?.reload()
        case .codexExecutable, .paceThreshold:
            break
        }
        coordinator.settingsDidChange(change)
    }

    private func scheduleTimers() {
        refreshTimer?.invalidate()
        markerTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.coordinator.requestRefresh() }
        }

        markerTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.coordinator.recalculatePaceOrRefresh() }
        }
    }

    @objc private func systemDidWake() {
        coordinator.requestRefresh()
        try? taskMonitorCoordinator?.rescan()
    }

    private func showTaskMonitor() {
        guard settings.taskMonitorEnabled || uiProofMode else {
            settingsWindowController?.show()
            return
        }

        settingsWindowController?.close()
        NSApp.activate(ignoringOtherApps: true)

        if let taskMonitorStatusBarController {
            taskMonitorStatusBarController.show()
            return
        }

        guard let model = ensureTaskMonitorModel() else {
            return
        }
        taskMonitorStatusBarController = TaskMonitorStatusBarController(model: model)
        taskMonitorStatusBarController?.show()
    }

    private func ensureTaskMonitorModel() -> TaskMonitorViewModel? {
        if let taskMonitorViewModel {
            statusBarController?.setTaskMonitorModel(
                settings.mainTaskSummaryEnabled || uiProofMode ? taskMonitorViewModel : nil
            )
            return taskMonitorViewModel
        }

        guard settings.taskMonitorEnabled || uiProofMode else {
            return nil
        }

        do {
            let monitor: TaskMonitorCoordinator
            if uiProofMode {
                let directory = try makeUIProofDirectory()
                uiProofDirectory = directory
                monitor = try TaskMonitorCoordinator(
                    catalog: CodexSessionLogCatalog(rootURL: directory),
                    databaseURL: directory.appendingPathComponent("tasks.sqlite")
                )
            } else {
                monitor = try TaskMonitorCoordinator()
            }
            monitor.onError = { error in
                NSLog("Codex Pace Bar task monitor error: \(error.localizedDescription)")
            }
            try monitor.start()
            taskMonitorCoordinator = monitor
            let model = TaskMonitorViewModel(
                coordinator: monitor,
                focusLoadEnabled: settings.focusLoadEnabled,
                planAwareEstimatesEnabled: settings.planAwareEstimatesEnabled
            )
            model.onActivityReloaded = { [weak self] tasks, goals, swarms in
                guard let self else { return }
                self.taskNotificationController.notifyIfNeeded(
                    for: tasks,
                    goals: goals,
                    swarms: swarms,
                    localEnabled: self.settings.taskNotificationsEnabled,
                    mobileEnabled: self.settings.mobileTaskNotificationsEnabled,
                    mobileTopic: self.settings.mobileNotificationTopic,
                    mobileDetailsEnabled: self.settings.mobileNotificationDetailsEnabled,
                    silentGoalsAndSwarmsEnabled: self.settings.silentGoalsAndSwarmsEnabled
                )
            }
            taskMonitorViewModel = model
            statusBarController?.setTaskMonitorModel(
                settings.mainTaskSummaryEnabled || uiProofMode ? model : nil
            )
            return model
        } catch {
            NSLog("Codex Pace Bar task monitor could not start: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeUIProofDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarUIProof-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = Date().timeIntervalSince1970
        var lines = [
            #"{"type":"session_meta","payload":{"id":"ui-proof-session","session_id":"ui-proof-session","cwd":"/ui-proof/codex-pace-bar"}}"#
        ]
        for index in 0..<12 {
            let turnID = "history-\(index)"
            let duration = 600 + Double(index * 60)
            let completedAt = now - 3_600 - Double(index * 120)
            let startedAt = completedAt - duration
            lines.append(#"{"type":"turn_context","payload":{"turn_id":"\#(turnID)","model":"gpt-5.6","effort":"high","cwd":"/ui-proof/codex-pace-bar"}}"#)
            lines.append(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"\#(turnID)","started_at":\#(startedAt)}}"#)
            lines.append(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"\#(turnID)","completed_at":\#(completedAt),"duration_ms":\#(duration * 1000)}} "#.trimmingCharacters(in: .whitespaces))
        }
        let currentStartedAt = now - 600
        lines.append(#"{"type":"turn_context","payload":{"turn_id":"ui-proof-current","model":"gpt-5.6","effort":"high","cwd":"/ui-proof/codex-pace-bar"}}"#)
        lines.append(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"ui-proof-current","started_at":\#(currentStartedAt)}}"#)
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: directory.appendingPathComponent("ui-proof-session.jsonl"))
        return directory
    }

    private func installTaskHooks() throws {
        guard let forwarderURL = taskHookForwarderURL() else { return }
        guard FileManager.default.isExecutableFile(atPath: forwarderURL.path) else {
            return
        }
        try hookInstaller.install(forwarderURL: forwarderURL)
    }

    private func taskHookSetupStatus() -> CodexHookSetupStatus {
        guard let forwarderURL = taskHookForwarderURL() else { return .notConfigured }
        return hookInstaller.setupStatus(forwarderURL: forwarderURL)
    }

    private func taskHookForwarderURL() -> URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("CodexPaceBarHookForwarder")
    }

    private func startTaskMonitorAfterCoreRefreshIfNeeded() {
        guard settings.requiresBackgroundTaskMonitoring else {
            return
        }
        deferredTaskMonitorStart?.cancel()
        deferredTaskMonitorStart = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            while self.model.isRefreshing || (self.model.snapshot == nil && self.model.failure == nil) {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            self.reconcileTaskMonitorRuntime()
            self.deferredTaskMonitorStart = nil
        }
    }

    private func reconcileTaskMonitorRuntime() {
        if settings.requiresBackgroundTaskMonitoring {
            _ = ensureTaskMonitorModel()
            return
        }

        statusBarController?.setTaskMonitorModel(nil)
        guard taskMonitorStatusBarController == nil else {
            return
        }
        stopTaskMonitorRuntime()
    }

    private func stopTaskMonitorRuntime() {
        taskNotificationController.resetMobileBaseline()
        taskMonitorCoordinator?.stop()
        taskMonitorCoordinator = nil
        taskMonitorViewModel = nil
        statusBarController?.setTaskMonitorModel(nil)
    }

    private func stopTaskMonitor() {
        deferredTaskMonitorStart?.cancel()
        deferredTaskMonitorStart = nil
        stopTaskMonitorRuntime()
        taskMonitorStatusBarController?.stop()
        taskMonitorStatusBarController = nil
    }
}
