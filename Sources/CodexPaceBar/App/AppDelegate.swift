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
    private var refreshTimer: Timer?
    private var markerTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(
            settings: settings,
            launchAtLogin: launchAtLogin
        )
        statusBarController = StatusBarController(
            model: model,
            settings: settings,
            history: history,
            onRefresh: { [weak self] in self?.coordinator.requestRefresh() },
            onOpenSettings: { [weak self] in self?.settingsWindowController?.show() },
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
        coordinator.requestRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        markerTimer?.invalidate()
        Task { await coordinator.shutdown() }
    }

    private func settingsDidChange(_ change: SettingsStore.Change) {
        switch change {
        case .refreshInterval:
            scheduleTimers()
        case .display:
            statusBarController?.refreshIcon()
        case .codexExecutable, .forecastMode, .paceThreshold:
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
    }
}
