import Foundation

public enum UsageForecaster {
    public static let minimumHistoryDuration: TimeInterval = 60 * 60
    public static let lookbackDuration: TimeInterval = 24 * 60 * 60

    public static func forecast(samples: [UsageSample], now: Date) -> UsageForecast? {
        guard let latest = samples
            .filter({ $0.timestamp <= now })
            .max(by: { $0.timestamp < $1.timestamp }),
              latest.resetAt > now
        else {
            return nil
        }

        let lookbackStart = latest.timestamp.addingTimeInterval(-lookbackDuration)
        let currentWindowSamples = samples
            .filter {
                $0.limitId == latest.limitId
                    && $0.resetAt == latest.resetAt
                    && $0.timestamp >= lookbackStart
                    && $0.timestamp <= latest.timestamp
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = currentWindowSamples.first,
              currentWindowSamples.count >= 2
        else {
            return nil
        }

        let historyDuration = latest.timestamp.timeIntervalSince(first.timestamp)
        guard historyDuration >= minimumHistoryDuration else {
            return nil
        }

        let historyHours = historyDuration / 3600
        let consumedPercentagePoints = latest.usedPercent - first.usedPercent
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
