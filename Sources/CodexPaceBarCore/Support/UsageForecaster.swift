import Foundation

public enum UsageForecaster {
    public static let minimumSampleCount = 3
    public static let minimumHistoryDuration: TimeInterval = 30 * 60
    public static let minimumUsageChange = 1.0
    public static let lookbackDuration: TimeInterval = 24 * 60 * 60

    public static func forecast(samples: [UsageSample], now: Date) -> UsageForecast? {
        let currentSeries = UsageHistorySeries.current(from: samples, now: now)
        guard let latest = currentSeries.last,
              latest.resetAt > now
        else {
            return nil
        }

        let lookbackStart = latest.timestamp.addingTimeInterval(-lookbackDuration)
        let currentWindowSamples = currentSeries
            .filter {
                $0.timestamp >= lookbackStart
                    && $0.timestamp <= latest.timestamp
            }

        guard let first = currentWindowSamples.first,
              currentWindowSamples.count >= minimumSampleCount
        else {
            return nil
        }

        let historyDuration = latest.timestamp.timeIntervalSince(first.timestamp)
        guard historyDuration >= minimumHistoryDuration else {
            return nil
        }

        let historyHours = historyDuration / 3600
        let consumedPercentagePoints = latest.usedPercent - first.usedPercent
        guard consumedPercentagePoints >= minimumUsageChange else {
            return nil
        }

        let rate = consumedPercentagePoints / historyHours
        guard rate.isFinite, rate > 0 else {
            return nil
        }

        let remainingPercentagePoints = max(0, 100 - latest.usedPercent)
        let hoursUntilExhaustion = remainingPercentagePoints / rate
        guard hoursUntilExhaustion.isFinite else {
            return nil
        }

        return UsageForecast(
            ratePercentagePointsPerHour: rate,
            exhaustionAt: latest.timestamp.addingTimeInterval(hoursUntilExhaustion * 3600),
            resetAt: latest.resetAt
        )
    }
}
