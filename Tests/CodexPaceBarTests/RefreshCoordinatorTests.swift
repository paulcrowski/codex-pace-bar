@testable import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct RefreshCoordinatorTests {
    @Test
    func timeoutBecomesRefreshFailure() async throws {
        let model = AppModel()
        let settings = SettingsStore(defaults: makeDefaults())
        let history = UsageHistoryStore(fileURL: temporaryHistoryURL())
        let fetcher = MockFetcher(outcome: .failure(.appServerTimeout("rateLimits")))
        let coordinator = makeCoordinator(model: model, settings: settings, history: history, fetchers: [fetcher])

        coordinator.requestRefresh()
        try await settle()

        #expect(model.failure == .refreshFailed("Timed out while waiting for rateLimits."))
        #expect(model.displayState == .error)
        #expect(fetcher.fetchCount == 1)
    }

    @Test
    func successfulRefreshUpdatesModelAndHistoryErrorIsVisible() async throws {
        let model = AppModel()
        let settings = SettingsStore(defaults: makeDefaults())
        let history = UsageHistoryStore(fileURL: URL(fileURLWithPath: "/dev/null/usage-history.json"))
        let fetcher = MockFetcher(outcome: .success(makeFetchResult(usedPercent: 35)))
        let coordinator = makeCoordinator(model: model, settings: settings, history: history, fetchers: [fetcher])

        coordinator.requestRefresh()
        try await settle()

        #expect(model.snapshot?.actualUsedPercent == 35)
        #expect(model.selectedWindow?.limitId == "codex")
        #expect(history.lastPersistenceError != nil)
        #expect(fetcher.fetchCount == 1)
    }

    @Test
    func fastRefreshRequestsAreQueuedOnce() async throws {
        let model = AppModel()
        let settings = SettingsStore(defaults: makeDefaults())
        let history = UsageHistoryStore(fileURL: temporaryHistoryURL())
        let fetcher = MockFetcher(outcome: .delayedThenSuccess(
            makeFetchResult(usedPercent: 10),
            makeFetchResult(usedPercent: 20),
            nanoseconds: 30_000_000
        ))
        let coordinator = makeCoordinator(model: model, settings: settings, history: history, fetchers: [fetcher])

        coordinator.requestRefresh()
        coordinator.requestRefresh()
        coordinator.requestRefresh()
        try await settle(nanoseconds: 150_000_000)

        #expect(fetcher.fetchCount == 2)
        #expect(model.snapshot?.actualUsedPercent == 20)
    }

    @Test
    func changingExecutableCancelsOldFetchAndUsesNewService() async throws {
        let model = AppModel()
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        let history = UsageHistoryStore(fileURL: temporaryHistoryURL())
        let resolver = MutableResolver(url: URL(fileURLWithPath: "/tmp/codex-one"))
        let first = MockFetcher(outcome: .delayed(makeFetchResult(usedPercent: 10), nanoseconds: 1_000_000_000))
        let second = MockFetcher(outcome: .success(makeFetchResult(usedPercent: 25)))
        let coordinator = makeCoordinator(
            model: model,
            settings: settings,
            history: history,
            resolver: resolver,
            fetchers: [first, second]
        )

        coordinator.requestRefresh()
        try await settle(nanoseconds: 10_000_000)
        resolver.url = URL(fileURLWithPath: "/tmp/codex-two")
        settings.codexExecutablePath = "codex-two"
        coordinator.settingsDidChange(.codexExecutable)
        try await settle(nanoseconds: 100_000_000)

        #expect(first.fetchCount == 1)
        #expect(second.fetchCount == 1)
        #expect(model.snapshot?.actualUsedPercent == 25)
    }

    @Test
    func expiredWindowRequestsARefreshWhenPaceIsRecalculated() async throws {
        let model = AppModel()
        let settings = SettingsStore(defaults: makeDefaults())
        let history = UsageHistoryStore(fileURL: temporaryHistoryURL())
        let clock = FixedClock(now: Date(timeIntervalSince1970: 5_000))
        let fetcher = MockFetcher(outcome: .success(makeFetchResult(usedPercent: 40, resetAt: Date(timeIntervalSince1970: 4_000))))
        let coordinator = makeCoordinator(model: model, settings: settings, history: history, clock: clock, fetchers: [fetcher])
        let window = CodexLimitWindow(
            limitId: "codex",
            source: "test",
            usedPercent: 40,
            windowDurationMins: 10080,
            resetsAt: Date(timeIntervalSince1970: 4_000)
        )
        model.apply(
            window: window,
            snapshot: PaceSnapshot(
                actualUsedPercent: 40,
                remainingPercent: 60,
                idealUsedPercent: 40,
                deltaPercentagePoints: 0,
                usedFraction: 0.4,
                elapsedFraction: 0.4,
                resetAt: window.resetsAt,
                state: .onPace,
                fetchedAt: clock.now,
                isStale: false
            ),
            forecast: nil,
            debugInfo: RedactedDebugInfo()
        )

        coordinator.recalculatePaceOrRefresh()
        try await settle()

        #expect(fetcher.fetchCount == 1)
        #expect(model.snapshot?.actualUsedPercent == 40)
    }

    @Test
    func errorAfterResetMarksSnapshotStale() async throws {
        let model = AppModel()
        let settings = SettingsStore(defaults: makeDefaults())
        let history = UsageHistoryStore(fileURL: temporaryHistoryURL())
        let clock = FixedClock(now: Date(timeIntervalSince1970: 5_000))
        let fetcher = MockFetcher(outcome: .failure(.appServerTimeout("rateLimits")))
        let coordinator = makeCoordinator(model: model, settings: settings, history: history, clock: clock, fetchers: [fetcher])
        let oldReset = Date(timeIntervalSince1970: 4_000)
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 60, windowDurationMins: 10080, resetsAt: oldReset)
        model.apply(
            window: window,
            snapshot: PaceSnapshot(actualUsedPercent: 60, remainingPercent: 40, idealUsedPercent: 50, deltaPercentagePoints: 10, usedFraction: 0.6, elapsedFraction: 0.5, resetAt: oldReset, state: .abovePace, fetchedAt: clock.now, isStale: false),
            forecast: nil,
            debugInfo: RedactedDebugInfo()
        )

        coordinator.requestRefresh()
        try await settle()

        #expect(model.snapshot?.isStale == true)
        #expect(model.snapshot?.state == .error)
        #expect(model.failure?.message.contains("may have reset") == true)
    }

    private func makeCoordinator(
        model: AppModel,
        settings: SettingsStore,
        history: UsageHistoryStore,
        resolver: MutableResolver = MutableResolver(url: URL(fileURLWithPath: "/tmp/codex")),
        clock: FixedClock = FixedClock(now: Date(timeIntervalSince1970: 2_000)),
        fetchers: [MockFetcher]
    ) -> RefreshCoordinator {
        let factory = MockFactory(fetchers: fetchers)
        return RefreshCoordinator(
            model: model,
            settings: settings,
            history: history,
            resolver: resolver,
            clock: clock,
            makeService: { _ in factory.make() }
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "RefreshCoordinatorTests-" + UUID().uuidString)!
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshCoordinatorTests-" + UUID().uuidString)
            .appendingPathComponent("usage-history.json")
    }

    private func settle(nanoseconds: UInt64 = 30_000_000) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func makeFetchResult(usedPercent: Double, resetAt: Date = Date(timeIntervalSince1970: 10_000)) -> RateLimitFetchResult {
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: usedPercent, windowDurationMins: 10080, resetsAt: resetAt)
        return RateLimitFetchResult(selection: RateLimitSelection(window: window, candidates: []), debugInfo: RedactedDebugInfo())
    }
}

private final class MockFactory: @unchecked Sendable {
    private var fetchers: [MockFetcher]

    init(fetchers: [MockFetcher]) {
        self.fetchers = fetchers
    }

    func make() -> MockFetcher {
        fetchers.removeFirst()
    }
}

@MainActor
private final class MockFetcher: RateLimitFetching {
    enum Outcome: Sendable {
        case success(RateLimitFetchResult)
        case failure(PaceError)
        case delayed(RateLimitFetchResult, nanoseconds: UInt64)
        case delayedThenSuccess(RateLimitFetchResult, RateLimitFetchResult, nanoseconds: UInt64)
    }

    let outcome: Outcome
    private(set) var fetchCount = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func fetchWeeklyLimit() async throws -> RateLimitFetchResult {
        fetchCount += 1
        switch outcome {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case let .delayed(result, nanoseconds):
            try await Task.sleep(nanoseconds: nanoseconds)
            return result
        case let .delayedThenSuccess(first, second, nanoseconds):
            if fetchCount == 1 {
                try await Task.sleep(nanoseconds: nanoseconds)
                return first
            }
            return second
        }
    }

    func shutdown() {}
}

private struct FixedClock: RefreshClock {
    let now: Date
}

private final class MutableResolver: @unchecked Sendable, CodexExecutableResolving {
    var url: URL

    init(url: URL) {
        self.url = url
    }

    func resolve(configuredPath: String?) throws -> URL {
        url
    }
}
