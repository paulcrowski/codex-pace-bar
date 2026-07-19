@testable import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Testing

@MainActor
@Suite
struct AppSupportTests {
    @Test
    func experimentalFeaturesDefaultToOff() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let settings = SettingsStore(defaults: defaults)

        #expect(!settings.taskMonitorEnabled)
        #expect(!settings.mainTaskSummaryEnabled)
        #expect(!settings.focusLoadEnabled)
        #expect(!settings.taskNotificationsEnabled)
        #expect(!settings.mobileTaskNotificationsEnabled)
        #expect(!settings.mobileNotificationDetailsEnabled)
        #expect(!settings.silentGoalsAndSwarmsEnabled)
        #expect(settings.mobileNotificationTopic.isEmpty)
    }

    @Test
    func backgroundMonitoringRequiresParentAndConsumer() {
        let defaults = UserDefaults(suiteName: "CodexPaceBarTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)

        settings.focusLoadEnabled = true
        #expect(!settings.requiresBackgroundTaskMonitoring)

        settings.taskMonitorEnabled = true
        #expect(!settings.requiresBackgroundTaskMonitoring)

        settings.mainTaskSummaryEnabled = true
        #expect(settings.requiresBackgroundTaskMonitoring)

        settings.mainTaskSummaryEnabled = false
        settings.mobileTaskNotificationsEnabled = true
        settings.mobileNotificationDetailsEnabled = true
        settings.silentGoalsAndSwarmsEnabled = true
        #expect(settings.requiresBackgroundTaskMonitoring)

        settings.taskMonitorEnabled = false
        #expect(!settings.requiresBackgroundTaskMonitoring)
    }

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
        settings.taskMonitorEnabled = true
        settings.mainTaskSummaryEnabled = true
        settings.focusLoadEnabled = true
        settings.taskNotificationsEnabled = true
        settings.mobileTaskNotificationsEnabled = true
        settings.mobileNotificationDetailsEnabled = true
        settings.silentGoalsAndSwarmsEnabled = true

        #expect(settings.refreshIntervalSeconds == SettingsStore.minimumRefreshInterval)
        #expect(settings.deltaThresholdPercentagePoints == SettingsStore.maximumDeltaThreshold)
        #expect(SettingsStore(defaults: defaults).codexExecutablePath == "/tmp/test-codex")
        #expect(SettingsStore(defaults: defaults).taskMonitorEnabled == true)
        #expect(SettingsStore(defaults: defaults).mainTaskSummaryEnabled == true)
        #expect(SettingsStore(defaults: defaults).focusLoadEnabled == true)
        #expect(SettingsStore(defaults: defaults).taskNotificationsEnabled == true)
        #expect(SettingsStore(defaults: defaults).mobileTaskNotificationsEnabled == true)
        #expect(SettingsStore(defaults: defaults).mobileNotificationDetailsEnabled == true)
        #expect(SettingsStore(defaults: defaults).silentGoalsAndSwarmsEnabled == true)
        #expect(!SettingsStore(defaults: defaults).mobileNotificationTopic.isEmpty)
        #expect(SettingsStore(defaults: defaults).refreshIntervalSeconds == SettingsStore.minimumRefreshInterval)
        #expect(SettingsStore(defaults: defaults).deltaThresholdPercentagePoints == SettingsStore.maximumDeltaThreshold)
    }

    @Test
    func settingsEmitChangesForCoordinatorInputs() {
        let settings = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        settings.onChange = { changes.append($0) }

        settings.codexExecutablePath = "custom-codex"
        settings.taskMonitorEnabled.toggle()
        settings.mainTaskSummaryEnabled.toggle()
        settings.focusLoadEnabled.toggle()
        settings.taskNotificationsEnabled.toggle()
        settings.mobileTaskNotificationsEnabled.toggle()
        settings.mobileNotificationDetailsEnabled.toggle()
        settings.silentGoalsAndSwarmsEnabled.toggle()
        settings.refreshIntervalSeconds = 600
        settings.historyBasedForecastEnabled.toggle()
        settings.deltaThresholdPercentagePoints = 5
        settings.barColorScheme = .statusColor

        #expect(changes.count == 12)
        #expect(changes.contains { if case .codexExecutable = $0 { true } else { false } })
        #expect(changes.contains { if case .taskMonitor = $0 { true } else { false } })
        #expect(changes.contains { if case .mainTaskSummary = $0 { true } else { false } })
        #expect(changes.contains { if case .focusLoad = $0 { true } else { false } })
        #expect(changes.contains { if case .taskNotifications = $0 { true } else { false } })
        #expect(changes.contains { if case .mobileTaskNotifications = $0 { true } else { false } })
        #expect(changes.contains { if case .refreshInterval = $0 { true } else { false } })
        #expect(changes.contains { if case .forecastMode = $0 { true } else { false } })
        #expect(changes.contains { if case .paceThreshold = $0 { true } else { false } })
        #expect(changes.contains { if case .display = $0 { true } else { false } })
    }

    @Test
    func mobileNotificationsGenerateAndPersistPrivateTopicOnlyWhenEnabled() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = SettingsStore(defaults: defaults)

        settings.mobileTaskNotificationsEnabled = true
        let topic = settings.mobileNotificationTopic

        #expect(topic.hasPrefix("codex-pace-bar-"))
        #expect(topic.count <= 64)
        #expect(topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(SettingsStore(defaults: defaults).mobileNotificationTopic == topic)

        settings.regenerateMobileNotificationTopic()
        #expect(settings.mobileNotificationTopic != topic)
    }

    @Test
    func enabledLegacyMobileSettingRepairsMissingTopicOnLoad() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set(true, forKey: "mobileTaskNotificationsEnabled")

        let settings = SettingsStore(defaults: defaults)

        #expect(settings.mobileTaskNotificationsEnabled)
        #expect(settings.mobileNotificationTopic.hasPrefix("codex-pace-bar-"))
        #expect(SettingsStore(defaults: defaults).mobileNotificationTopic == settings.mobileNotificationTopic)
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
