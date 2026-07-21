import Foundation

public enum UsageForecaster {
    public enum Mode: Sendable {
        case recentPace
        case historyBased
    }

    public static let minimumSampleCount = 3
    public static let minimumHistoryDuration: TimeInterval = 30 * 60
    public static let minimumUsageChange = 1.0
    public static let lookbackDuration: TimeInterval = 24 * 60 * 60
    public static let historyLookbackDuration = UsageHistoryRepository.retentionDuration

    public static func forecast(
        samples: [UsageSample],
        now: Date,
        mode: Mode,
        calendar: Calendar = .current
    ) -> UsageForecast? {
        switch mode {
        case .recentPace:
            recentPaceForecast(samples: samples, now: now)
        case .historyBased:
            UsagePatternForecaster.forecast(samples: samples, now: now, calendar: calendar)
                ?? recentPaceForecast(samples: samples, now: now)
        }
    }

    private static func recentPaceForecast(samples: [UsageSample], now: Date) -> UsageForecast? {
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

        let exhaustionAt = latest.timestamp.addingTimeInterval(hoursUntilExhaustion * 3600)
        let projectionEnd = min(exhaustionAt, latest.resetAt)
        let projectionHours = projectionEnd.timeIntervalSince(latest.timestamp) / 3600
        var projection = [
            UsageForecastPoint(timestamp: latest.timestamp, usedPercent: latest.usedPercent)
        ]
        if projectionEnd > latest.timestamp {
            projection.append(UsageForecastPoint(
                timestamp: projectionEnd,
                usedPercent: latest.usedPercent + rate * projectionHours
            ))
        }

        return UsageForecast(
            projection: projection,
            exhaustionAt: exhaustionAt,
            resetAt: latest.resetAt
        )
    }
}
