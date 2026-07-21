import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public enum Change {
        case codexExecutable
        case focusLoad
        case taskMonitor
        case mainTaskSummary
        case taskNotifications
        case mobileTaskNotifications
        case refreshInterval
        case forecastMode
        case paceThreshold
        case display
    }

    public static let minimumRefreshInterval = 60
    public static let defaultRefreshInterval = 300
    public static let maximumRefreshInterval = 3600
    public static let minimumDeltaThreshold = 1
    public static let defaultDeltaThreshold = 2
    public static let maximumDeltaThreshold = 20

    public var notificationsEnabled: Bool {
        didSet {
            guard notificationsEnabled != oldValue else {
                return
            }
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    public var taskMonitorEnabled: Bool {
        didSet {
            guard taskMonitorEnabled != oldValue else {
                return
            }
            defaults.set(taskMonitorEnabled, forKey: Keys.taskMonitorEnabled)
            onChange?(.taskMonitor)
        }
    }

    public var mainTaskSummaryEnabled: Bool {
        didSet {
            guard mainTaskSummaryEnabled != oldValue else {
                return
            }
            defaults.set(mainTaskSummaryEnabled, forKey: Keys.mainTaskSummaryEnabled)
            onChange?(.mainTaskSummary)
        }
    }

    public var focusLoadEnabled: Bool {
        didSet {
            guard focusLoadEnabled != oldValue else {
                return
            }
            defaults.set(focusLoadEnabled, forKey: Keys.focusLoadEnabled)
            onChange?(.focusLoad)
        }
    }

    public var taskNotificationsEnabled: Bool {
        didSet {
            guard taskNotificationsEnabled != oldValue else { return }
            defaults.set(taskNotificationsEnabled, forKey: Keys.taskNotificationsEnabled)
            onChange?(.taskNotifications)
        }
    }

    public var mobileTaskNotificationsEnabled: Bool {
        didSet {
            guard mobileTaskNotificationsEnabled != oldValue else { return }
            if mobileTaskNotificationsEnabled, mobileNotificationTopic.isEmpty {
                mobileNotificationTopic = Self.makeMobileNotificationTopic()
            }
            defaults.set(mobileTaskNotificationsEnabled, forKey: Keys.mobileTaskNotificationsEnabled)
            onChange?(.mobileTaskNotifications)
        }
    }

    public var mobileNotificationDetailsEnabled: Bool {
        didSet {
            guard mobileNotificationDetailsEnabled != oldValue else { return }
            defaults.set(mobileNotificationDetailsEnabled, forKey: Keys.mobileNotificationDetailsEnabled)
            onChange?(.mobileTaskNotifications)
        }
    }

    public var silentGoalsAndSwarmsEnabled: Bool {
        didSet {
            guard silentGoalsAndSwarmsEnabled != oldValue else { return }
            defaults.set(silentGoalsAndSwarmsEnabled, forKey: Keys.silentGoalsAndSwarmsEnabled)
            onChange?(.mobileTaskNotifications)
        }
    }

    public private(set) var mobileNotificationTopic: String {
        didSet {
            guard mobileNotificationTopic != oldValue else { return }
            defaults.set(mobileNotificationTopic, forKey: Keys.mobileNotificationTopic)
        }
    }

    public func regenerateMobileNotificationTopic() {
        mobileNotificationTopic = Self.makeMobileNotificationTopic()
        onChange?(.mobileTaskNotifications)
    }

    public var requiresBackgroundTaskMonitoring: Bool {
        taskMonitorEnabled && (
            mainTaskSummaryEnabled || taskNotificationsEnabled || mobileTaskNotificationsEnabled
        )
    }

    public var historyBasedForecastEnabled: Bool {
        didSet {
            guard historyBasedForecastEnabled != oldValue else {
                return
            }
            defaults.set(historyBasedForecastEnabled, forKey: Keys.historyBasedForecastEnabled)
            onChange?(.forecastMode)
        }
    }

    public var planAwareEstimatesEnabled: Bool {
        didSet {
            guard planAwareEstimatesEnabled != oldValue else { return }
            defaults.set(planAwareEstimatesEnabled, forKey: Keys.planAwareEstimatesEnabled)
            onChange?(.forecastMode)
        }
    }

    public var codexExecutablePath: String {
        didSet {
            guard codexExecutablePath != oldValue else {
                return
            }
            defaults.set(codexExecutablePath, forKey: Keys.codexExecutablePath)
            onChange?(.codexExecutable)
        }
    }

    public var refreshIntervalSeconds: Int {
        didSet {
            let clamped = Self.clampRefreshInterval(refreshIntervalSeconds)
            if clamped != refreshIntervalSeconds {
                refreshIntervalSeconds = clamped
                return
            }
            guard refreshIntervalSeconds != oldValue else {
                return
            }
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
            onChange?(.refreshInterval)
        }
    }

    public var deltaThresholdPercentagePoints: Int {
        didSet {
            let clamped = Self.clampDeltaThreshold(deltaThresholdPercentagePoints)
            if clamped != deltaThresholdPercentagePoints {
                deltaThresholdPercentagePoints = clamped
                return
            }
            guard deltaThresholdPercentagePoints != oldValue else {
                return
            }
            defaults.set(deltaThresholdPercentagePoints, forKey: Keys.deltaThresholdPercentagePoints)
            onChange?(.paceThreshold)
        }
    }

    public var barColorScheme: BarColorScheme {
        didSet {
            guard barColorScheme != oldValue else {
                return
            }
            defaults.set(barColorScheme.rawValue, forKey: Keys.barColorScheme)
            onChange?(.display)
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    public var onChange: ((Change) -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.taskMonitorEnabled = defaults.object(forKey: Keys.taskMonitorEnabled) as? Bool ?? false
        self.mainTaskSummaryEnabled = defaults.object(forKey: Keys.mainTaskSummaryEnabled) as? Bool ?? false
        self.focusLoadEnabled = defaults.object(forKey: Keys.focusLoadEnabled) as? Bool ?? false
        self.taskNotificationsEnabled = defaults.object(forKey: Keys.taskNotificationsEnabled) as? Bool ?? false
        let storedMobileNotificationsEnabled = defaults.object(
            forKey: Keys.mobileTaskNotificationsEnabled
        ) as? Bool ?? false
        let storedMobileTopic = defaults.string(forKey: Keys.mobileNotificationTopic) ?? ""
        let initialMobileTopic = storedMobileNotificationsEnabled && storedMobileTopic.isEmpty
            ? Self.makeMobileNotificationTopic()
            : storedMobileTopic
        self.mobileTaskNotificationsEnabled = storedMobileNotificationsEnabled
        self.mobileNotificationDetailsEnabled = defaults.object(
            forKey: Keys.mobileNotificationDetailsEnabled
        ) as? Bool ?? false
        self.silentGoalsAndSwarmsEnabled = defaults.object(
            forKey: Keys.silentGoalsAndSwarmsEnabled
        ) as? Bool ?? false
        self.mobileNotificationTopic = initialMobileTopic
        if initialMobileTopic != storedMobileTopic {
            defaults.set(initialMobileTopic, forKey: Keys.mobileNotificationTopic)
        }
        self.historyBasedForecastEnabled = defaults.object(forKey: Keys.historyBasedForecastEnabled) as? Bool ?? true
        self.planAwareEstimatesEnabled = defaults.object(forKey: Keys.planAwareEstimatesEnabled) as? Bool ?? true
        self.codexExecutablePath = defaults.string(forKey: Keys.codexExecutablePath) ?? "codex"
        let storedInterval = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Int ?? Self.defaultRefreshInterval
        self.refreshIntervalSeconds = Self.clampRefreshInterval(storedInterval)
        let storedThreshold = defaults.object(forKey: Keys.deltaThresholdPercentagePoints) as? Int ?? Self.defaultDeltaThreshold
        self.deltaThresholdPercentagePoints = Self.clampDeltaThreshold(storedThreshold)
        let storedColorScheme = defaults.string(forKey: Keys.barColorScheme)
        self.barColorScheme = storedColorScheme.flatMap(BarColorScheme.init(rawValue:)) ?? .paceComparison
    }

    private static func clampRefreshInterval(_ value: Int) -> Int {
        min(max(value, minimumRefreshInterval), maximumRefreshInterval)
    }

    private static func clampDeltaThreshold(_ value: Int) -> Int {
        min(max(value, minimumDeltaThreshold), maximumDeltaThreshold)
    }

    private static func makeMobileNotificationTopic() -> String {
        "codex-pace-bar-\(UUID().uuidString.lowercased())"
    }

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let taskMonitorEnabled = "taskMonitorEnabled"
        static let mainTaskSummaryEnabled = "mainTaskSummaryEnabled"
        static let focusLoadEnabled = "focusLoadEnabled"
        static let taskNotificationsEnabled = "taskNotificationsEnabled"
        static let mobileTaskNotificationsEnabled = "mobileTaskNotificationsEnabled"
        static let mobileNotificationDetailsEnabled = "mobileNotificationDetailsEnabled"
        static let silentGoalsAndSwarmsEnabled = "silentGoalsAndSwarmsEnabled"
        static let mobileNotificationTopic = "mobileNotificationTopic"
        static let historyBasedForecastEnabled = "historyBasedForecastEnabled"
        static let planAwareEstimatesEnabled = "planAwareEstimatesEnabled"
        static let codexExecutablePath = "codexExecutablePath"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let deltaThresholdPercentagePoints = "deltaThresholdPercentagePoints"
        static let barColorScheme = "barColorScheme"
    }
}
