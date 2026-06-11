import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
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

    var codexExecutablePath: String {
        didSet {
            guard codexExecutablePath != oldValue else {
                return
            }
            defaults.set(codexExecutablePath, forKey: Keys.codexExecutablePath)
            onChange?()
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
            onChange?()
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
            onPaceThresholdChange?()
        }
    }

    var barColorScheme: BarColorScheme {
        didSet {
            guard barColorScheme != oldValue else {
                return
            }
            defaults.set(barColorScheme.rawValue, forKey: Keys.barColorScheme)
            onDisplayChange?()
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    var onChange: (() -> Void)?

    @ObservationIgnored
    var onPaceThresholdChange: (() -> Void)?

    @ObservationIgnored
    var onDisplayChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.codexExecutablePath = defaults.string(forKey: Keys.codexExecutablePath) ?? "codex"
        let storedInterval = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Int ?? Self.defaultRefreshInterval
        self.refreshIntervalSeconds = Self.clampRefreshInterval(storedInterval)
        let storedThreshold = defaults.object(forKey: Keys.deltaThresholdPercentagePoints) as? Int ?? Self.defaultDeltaThreshold
        self.deltaThresholdPercentagePoints = Self.clampDeltaThreshold(storedThreshold)
        let storedColorScheme = defaults.string(forKey: Keys.barColorScheme)
        self.barColorScheme = storedColorScheme.flatMap(BarColorScheme.init(rawValue:)) ?? .statusColor
    }

    private static func clampRefreshInterval(_ value: Int) -> Int {
        min(max(value, minimumRefreshInterval), maximumRefreshInterval)
    }

    private static func clampDeltaThreshold(_ value: Int) -> Int {
        min(max(value, minimumDeltaThreshold), maximumDeltaThreshold)
    }

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let codexExecutablePath = "codexExecutablePath"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let deltaThresholdPercentagePoints = "deltaThresholdPercentagePoints"
        static let barColorScheme = "barColorScheme"
    }
}
