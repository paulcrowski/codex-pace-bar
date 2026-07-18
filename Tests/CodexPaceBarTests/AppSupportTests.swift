@testable import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Testing

@MainActor
@Suite
struct AppSupportTests {
    @Test
    func settingsClampPersistAndReload() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.refreshIntervalSeconds == SettingsStore.defaultRefreshInterval)
        #expect(settings.deltaThresholdPercentagePoints == SettingsStore.defaultDeltaThreshold)

        settings.refreshIntervalSeconds = 10
        settings.deltaThresholdPercentagePoints = 99
        settings.codexExecutablePath = "/tmp/test-codex"

        #expect(settings.refreshIntervalSeconds == SettingsStore.minimumRefreshInterval)
        #expect(settings.deltaThresholdPercentagePoints == SettingsStore.maximumDeltaThreshold)
        #expect(SettingsStore(defaults: defaults).codexExecutablePath == "/tmp/test-codex")
        #expect(SettingsStore(defaults: defaults).refreshIntervalSeconds == SettingsStore.minimumRefreshInterval)
        #expect(SettingsStore(defaults: defaults).deltaThresholdPercentagePoints == SettingsStore.maximumDeltaThreshold)
    }

    @Test
    func settingsEmitChangesForCoordinatorInputs() {
        let settings = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        settings.onChange = { changes.append($0) }

        settings.codexExecutablePath = "custom-codex"
        settings.refreshIntervalSeconds = 600
        settings.historyBasedForecastEnabled.toggle()
        settings.deltaThresholdPercentagePoints = 5
        settings.barColorScheme = .statusColor

        #expect(changes.count == 5)
        #expect(changes.contains { if case .codexExecutable = $0 { true } else { false } })
        #expect(changes.contains { if case .refreshInterval = $0 { true } else { false } })
        #expect(changes.contains { if case .forecastMode = $0 { true } else { false } })
        #expect(changes.contains { if case .paceThreshold = $0 { true } else { false } })
        #expect(changes.contains { if case .display = $0 { true } else { false } })
    }

    @Test
    func historyStoreRecordsAndReloadsWindow() throws {
        try withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("usage-history.json")
            let timestamp = Date()
            let resetAt = timestamp.addingTimeInterval(24 * 60 * 60)
            let window = CodexLimitWindow(
                limitId: "codex",
                source: "test",
                usedPercent: 42,
                windowDurationMins: 10080,
                resetsAt: resetAt
            )

            let store = UsageHistoryStore(fileURL: fileURL)
            store.record(window: window, at: timestamp)
            let reloaded = UsageHistoryStore(fileURL: fileURL)

            #expect(store.lastPersistenceError == nil)
            #expect(reloaded.samples.count == 1)
            #expect(reloaded.samples.first?.usedPercent == 42)
            #expect(reloaded.samples.first?.limitId == "codex")
        }
    }

    @Test
    func appModelAppliesSnapshotAndNotifies() {
        let model = AppModel()
        var notificationCount = 0
        model.onChange = { notificationCount += 1 }
        let timestamp = Date()
        let window = CodexLimitWindow(
            limitId: "codex",
            source: "test",
            usedPercent: 20,
            windowDurationMins: 10080,
            resetsAt: timestamp.addingTimeInterval(24 * 60 * 60)
        )
        let snapshot = PaceSnapshot(
            actualUsedPercent: 20,
            remainingPercent: 80,
            idealUsedPercent: 10,
            deltaPercentagePoints: 10,
            usedFraction: 0.2,
            elapsedFraction: 0.1,
            resetAt: window.resetsAt,
            state: .abovePace,
            fetchedAt: timestamp,
            isStale: false
        )

        model.apply(window: window, snapshot: snapshot, forecast: nil, debugInfo: RedactedDebugInfo())

        #expect(model.snapshot == snapshot)
        #expect(model.selectedWindow == window)
        #expect(model.displayState == .abovePace)
        #expect(model.failure == nil)
        #expect(model.lastCheckedAt == timestamp)
        #expect(notificationCount == 1)
    }

    @Test
    func appModelClassifiesSetupAndStaleFailures() {
        let model = AppModel()
        model.applyError(PaceError.codexExecutableNotFound, staleAfterReset: false, executablePath: nil)
        #expect(model.failure?.requiresCodexSetup == true)
        #expect(model.displayState == .error)

        let snapshot = PaceSnapshot(
            actualUsedPercent: 50,
            remainingPercent: 50,
            idealUsedPercent: 50,
            deltaPercentagePoints: 0,
            usedFraction: 0.5,
            elapsedFraction: 0.5,
            resetAt: Date(timeIntervalSinceNow: -1),
            state: .onPace,
            fetchedAt: Date(),
            isStale: false
        )
        model.applyPaceOnly(snapshot: snapshot)
        model.applyError(PaceError.appServerTimeout("rateLimits"), staleAfterReset: true, executablePath: "/tmp/codex")

        #expect(model.failure?.requiresCodexSetup == false)
        #expect(model.failure?.message.contains("may have reset") == true)
        #expect(model.snapshot?.isStale == true)
        #expect(model.snapshot?.state == .error)
    }

    private let defaultsSuiteName = "CodexPaceBarAppSupportTests-" + UUID().uuidString

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName)!
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarAppSupportTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
