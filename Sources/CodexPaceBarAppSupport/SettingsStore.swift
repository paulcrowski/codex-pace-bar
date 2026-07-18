import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public enum Change {
        case codexExecutable
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

    public var historyBasedForecastEnabled: Bool {
        didSet {
            guard historyBasedForecastEnabled != oldValue else {
                return
            }
            defaults.set(historyBasedForecastEnabled, forKey: Keys.historyBasedForecastEnabled)
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
