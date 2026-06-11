@preconcurrency import AppKit
import CodexPaceBarCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var model = AppModel()
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var refreshTimer: Timer?
    private var markerTimer: Timer?
    private var resetTimer: Timer?
    private var service: RateLimitService?
    private var serviceExecutableURL: URL?
    private var refreshTask: Task<Void, Never>?
    private let notificationController = PaceNotificationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(settings: settings)
        statusBarController = StatusBarController(
            model: model,
            settings: settings,
            onRefresh: { [weak self] in self?.refreshNow() },
            onOpenSettings: { [weak self] in self?.settingsWindowController?.show() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        settings.onChange = { [weak self] in
            self?.settingsDidChange()
        }
        settings.onPaceThresholdChange = { [weak self] in
            self?.recalculatePaceOrRefresh(resetHysteresis: true)
        }
        settings.onDisplayChange = { [weak self] in
            self?.model.onChange?()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        scheduleTimers()
        refreshNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        markerTimer?.invalidate()
        resetTimer?.invalidate()
        refreshTask?.cancel()
        if let service {
            Task { await service.shutdown() }
        }
    }

    private func settingsDidChange() {
        refreshTimer?.invalidate()
        scheduleTimers()
        serviceExecutableURL = nil
        if let service {
            Task { await service.shutdown() }
        }
        service = nil
        refreshNow()
    }

    private func scheduleTimers() {
        refreshTimer?.invalidate()
        markerTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }

        markerTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recalculatePaceOrRefresh() }
        }
    }

    private func scheduleResetTimer(for resetAt: Date) {
        resetTimer?.invalidate()
        let now = Date()

        if now >= resetAt {
            refreshNow()
            return
        }

        let nearReset = resetAt.addingTimeInterval(-60)
        let fireDate = nearReset > now ? nearReset : resetAt
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        resetTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshNow() {
        guard model.isRefreshing else {
            refreshTask = Task { await performRefresh() }
            return
        }
    }

    private func performRefresh() async {
        model.showLoadingIfNeeded()
        model.setRefreshing(true)
        defer { model.setRefreshing(false) }

        let resolver = CodexExecutableResolver()
        var resolvedExecutable: URL?

        do {
            let executableURL = try resolver.resolve(configuredPath: settings.codexExecutablePath)
            resolvedExecutable = executableURL
            let rateLimitService = service(for: executableURL)
            let fetch = try await rateLimitService.fetchWeeklyLimit()
            let now = Date()
            let snapshot = PaceCalculator.snapshot(
                for: fetch.selection.window,
                now: now,
                fetchedAt: now,
                previousState: model.snapshot?.state,
                thresholds: paceThresholds
            )

            model.apply(window: fetch.selection.window, snapshot: snapshot, debugInfo: fetch.debugInfo)
            notificationController.notifyIfNeeded(snapshot: snapshot, settings: settings, now: now)
            scheduleResetTimer(for: fetch.selection.window.resetsAt)
        } catch {
            let staleAfterReset = model.snapshot.map { Date() >= $0.resetAt } ?? false
            model.applyError(error, staleAfterReset: staleAfterReset, executablePath: resolvedExecutable?.path)
        }
    }

    private func service(for executableURL: URL) -> RateLimitService {
        if serviceExecutableURL != executableURL {
            if let service {
                Task { await service.shutdown() }
            }
            service = RateLimitService(executableURL: executableURL)
            serviceExecutableURL = executableURL
        }

        if let service {
            return service
        }

        let newService = RateLimitService(executableURL: executableURL)
        service = newService
        serviceExecutableURL = executableURL
        return newService
    }

    private func recalculatePaceOrRefresh(resetHysteresis: Bool = false) {
        guard let window = model.selectedWindow, let existingSnapshot = model.snapshot else {
            refreshNow()
            return
        }

        let now = Date()
        guard now < window.resetsAt else {
            refreshNow()
            return
        }

        let snapshot = PaceCalculator.snapshot(
            for: window,
            now: now,
            fetchedAt: existingSnapshot.fetchedAt,
            previousState: resetHysteresis ? nil : existingSnapshot.state,
            isStale: existingSnapshot.isStale,
            thresholds: paceThresholds
        )
        model.applyPaceOnly(snapshot: snapshot)
        notificationController.notifyIfNeeded(snapshot: snapshot, settings: settings, now: now)
    }

    private var paceThresholds: PaceThresholds {
        PaceThresholds(deltaPercentagePoints: Double(settings.deltaThresholdPercentagePoints))
    }

    @objc private func systemDidWake() {
        refreshNow()
    }
}
