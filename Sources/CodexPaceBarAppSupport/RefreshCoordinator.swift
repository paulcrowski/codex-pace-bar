import CodexPaceBarCore
import Foundation

public protocol RateLimitFetching: AnyObject, Sendable {
    func fetchWeeklyLimit() async throws -> RateLimitFetchResult
    func shutdown() async
}

public protocol CodexExecutableResolving {
    func resolve(configuredPath: String?) throws -> URL
}

public protocol RefreshClock {
    var now: Date { get }
}

public struct SystemRefreshClock: RefreshClock {
    public init() {}

    public var now: Date { Date() }
}

extension RateLimitService: RateLimitFetching {}
extension CodexExecutableResolver: CodexExecutableResolving {}

@MainActor
public final class RefreshCoordinator {
    public typealias ServiceFactory = (URL) -> any RateLimitFetching
    public typealias NotificationHandler = (PaceSnapshot, UsageForecast?, Date) -> Void

    private let model: AppModel
    private let settings: SettingsStore
    private let history: UsageHistoryStore
    private let resolver: any CodexExecutableResolving
    private let clock: any RefreshClock
    private let makeService: ServiceFactory
    private let notificationHandler: NotificationHandler
    private var service: (any RateLimitFetching)?
    private var serviceExecutableURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var resetTimer: Timer?

    public init(
        model: AppModel,
        settings: SettingsStore,
        history: UsageHistoryStore,
        resolver: any CodexExecutableResolving = CodexExecutableResolver(),
        clock: any RefreshClock = SystemRefreshClock(),
        makeService: @escaping ServiceFactory = { RateLimitService(executableURL: $0) },
        notificationHandler: @escaping NotificationHandler = { _, _, _ in }
    ) {
        self.model = model
        self.settings = settings
        self.history = history
        self.resolver = resolver
        self.clock = clock
        self.makeService = makeService
        self.notificationHandler = notificationHandler
    }

    public func requestRefresh() {
        if refreshTask != nil {
            refreshRequested = true
            return
        }

        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    public func settingsDidChange(_ change: SettingsStore.Change) {
        switch change {
        case .codexExecutable:
            refreshTask?.cancel()
            invalidateService()
            requestRefresh()
        case .taskMonitor:
            break
        case .mainTaskSummary:
            break
        case .taskNotifications:
            break
        case .focusLoad:
            break
        case .refreshInterval:
            break
        case .forecastMode:
            requestRefresh()
        case .paceThreshold:
            recalculatePaceOrRefresh(resetHysteresis: true)
        case .display:
            break
        }
    }

    public func recalculatePaceOrRefresh(resetHysteresis: Bool = false) {
        guard let window = model.selectedWindow, let existingSnapshot = model.snapshot else {
            requestRefresh()
            return
        }

        let now = clock.now
        guard now < window.resetsAt else {
            requestRefresh()
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
        notifyIfNeeded(snapshot: snapshot, now: now)
    }

    public func shutdown() async {
        resetTimer?.invalidate()
        resetTimer = nil
        refreshRequested = false
        refreshTask?.cancel()
        refreshTask = nil
        if let service {
            await service.shutdown()
        }
        service = nil
        serviceExecutableURL = nil
    }

    private func performRefresh() async {
        model.showLoadingIfNeeded()
        model.setRefreshing(true)
        defer {
            model.setRefreshing(false)
            refreshTask = nil
            if refreshRequested {
                refreshRequested = false
                requestRefresh()
            }
        }

        let executableURL: URL
        do {
            executableURL = try resolver.resolve(configuredPath: settings.codexExecutablePath)
            let rateLimitService = service(for: executableURL)
            let fetch = try await rateLimitService.fetchWeeklyLimit()
            try Task.checkCancellation()
            let now = clock.now
            history.record(window: fetch.selection.window, at: now)
            let forecast = UsageForecaster.forecast(
                samples: history.samples,
                now: now,
                mode: settings.historyBasedForecastEnabled ? .historyBased : .recentPace
            )
            let snapshot = PaceCalculator.snapshot(
                for: fetch.selection.window,
                now: now,
                fetchedAt: now,
                previousState: model.snapshot?.state,
                thresholds: paceThresholds
            )

            model.apply(
                window: fetch.selection.window,
                snapshot: snapshot,
                forecast: forecast,
                debugInfo: fetch.debugInfo
            )
            notifyIfNeeded(snapshot: snapshot, now: now)
            scheduleResetTimer(for: fetch.selection.window.resetsAt)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            let now = clock.now
            let staleAfterReset = model.snapshot.map { now >= $0.resetAt } ?? false
            model.applyError(
                error,
                staleAfterReset: staleAfterReset,
                executablePath: serviceExecutableURL?.path,
                now: now
            )
        }
    }

    private func service(for executableURL: URL) -> any RateLimitFetching {
        if serviceExecutableURL != executableURL {
            invalidateService()
            service = makeService(executableURL)
            serviceExecutableURL = executableURL
        }

        if let service {
            return service
        }

        let newService = makeService(executableURL)
        service = newService
        serviceExecutableURL = executableURL
        return newService
    }

    private func invalidateService() {
        if let service {
            Task { await service.shutdown() }
        }
        service = nil
        serviceExecutableURL = nil
    }

    private func scheduleResetTimer(for resetAt: Date) {
        resetTimer?.invalidate()
        let now = clock.now

        if now >= resetAt {
            return
        }

        let nearReset = resetAt.addingTimeInterval(-60)
        let fireDate = nearReset > now ? nearReset : resetAt
        guard fireDate > Date() else {
            return
        }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.requestRefresh() }
        }
        resetTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func notifyIfNeeded(snapshot: PaceSnapshot, now: Date) {
        notificationHandler(snapshot, model.forecast, now)
    }

    private var paceThresholds: PaceThresholds {
        PaceThresholds(deltaPercentagePoints: Double(settings.deltaThresholdPercentagePoints))
    }
}
