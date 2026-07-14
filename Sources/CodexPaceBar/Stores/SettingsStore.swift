import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    enum Change {
        case codexExecutable
        case refreshInterval
        case forecastMode
        case paceThreshold
        case display
    }

    static let minimumRefreshInterval = 60
    static let defaultRefreshInterval = 300
    static let maximumRefreshInterval = 3600
    static let minimumDeltaThreshold = 1
    static let defaultDeltaThreshold = 2
    static let maximumDeltaThreshold = 20

    var notificationsEnabled: Bool {
        didSet {
            guard notificationsEnabled != oldValue else {
                return
            }
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    var historyBasedForecastEnabled: Bool {
        didSet {
            guard historyBasedForecastEnabled != oldValue else {
                return
            }
            defaults.set(historyBasedForecastEnabled, forKey: Keys.historyBasedForecastEnabled)
            onChange?(.forecastMode)
        }
    }

    var codexExecutablePath: String {
        didSet {
            guard codexExecutablePath != oldValue else {
                return
            }
            defaults.set(codexExecutablePath, forKey: Keys.codexExecutablePath)
            onChange?(.codexExecutable)
        }
    }

    var refreshIntervalSeconds: Int {
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

    var deltaThresholdPercentagePoints: Int {
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

    var barColorScheme: BarColorScheme {
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
    var onChange: ((Change) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.historyBasedForecastEnabled = defaults.object(forKey: Keys.historyBasedForecastEnabled) as? Bool ?? true
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

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let historyBasedForecastEnabled = "historyBasedForecastEnabled"
        static let codexExecutablePath = "codexExecutablePath"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let deltaThresholdPercentagePoints = "deltaThresholdPercentagePoints"
        static let barColorScheme = "barColorScheme"
    }
}
