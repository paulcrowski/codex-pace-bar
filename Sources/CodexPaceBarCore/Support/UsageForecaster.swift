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
    public static let recentSmoothingDuration: TimeInterval = 3 * 24 * 60 * 60
    public static let minimumSmoothedDuration: TimeInterval = 6 * 60 * 60
    public static let historyLookbackDuration = UsageHistoryRepository.retentionDuration

    private static let historicalWeight = 0.30
    private static let recentWeight = 0.50
    private static let todayWeight = 0.20

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
            historyBasedForecast(samples: samples, now: now, calendar: calendar)
        }
    }

    private static func historyBasedForecast(
        samples: [UsageSample],
        now: Date,
        calendar: Calendar
    ) -> UsageForecast? {
        guard let historical = UsagePatternForecaster.forecast(
            samples: samples,
            now: now,
            calendar: calendar
        ) else {
            return smoothedCurrentForecast(samples: samples, now: now, calendar: calendar)
                ?? recentPaceForecast(samples: samples, now: now)
        }

        let currentSeries = UsageHistorySeries.current(from: samples, now: now)
        let recentRate = smoothedRate(
            in: currentSeries,
            from: now.addingTimeInterval(-recentSmoothingDuration),
            through: now
        )
        let todayRate = smoothedRate(
            in: currentSeries,
            from: calendar.startOfDay(for: now),
            through: now
        )

        var weightedRates: [(rate: Double, weight: Double)] = [
            (historical.ratePercentagePointsPerHour, historicalWeight)
        ]
        if let recentRate {
            weightedRates.append((recentRate.rate, recentWeight))
        }
        if let todayRate {
            weightedRates.append((todayRate.rate, todayWeight))
        }

        let totalWeight = weightedRates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0,
              let currentUsedPercent = currentSeries.last?.usedPercent
        else {
            return historical
        }

        let blendedRate = weightedRates.reduce(0) { partial, item in
            partial + item.rate * item.weight
        } / totalWeight
        guard blendedRate > 0, blendedRate.isFinite else {
            return historical
        }
        let remainingPercentagePoints = max(0, 100 - currentUsedPercent)
        let scalarExhaustionAt = now.addingTimeInterval(remainingPercentagePoints / blendedRate * 3600)
        let blended = blendedProjection(
            historical: historical,
            currentUsedPercent: currentUsedPercent,
            targetRate: blendedRate,
            scalarExhaustionAt: scalarExhaustionAt,
            now: now
        )

        return UsageForecast(
            ratePercentagePointsPerHour: blendedRate,
            exhaustionAt: blended.exhaustionAt,
            resetAt: historical.resetAt,
            confidence: confidence(
                historicalRate: historical.ratePercentagePointsPerHour,
                recentRate: recentRate,
                todayRate: todayRate
            ),
            projection: blended.points
        )
    }

    private static func smoothedCurrentForecast(
        samples: [UsageSample],
        now: Date,
        calendar: Calendar
    ) -> UsageForecast? {
        let currentSeries = UsageHistorySeries.current(from: samples, now: now)
        guard let latest = currentSeries.last else {
            return nil
        }

        let recentRate = smoothedRate(
            in: currentSeries,
            from: now.addingTimeInterval(-recentSmoothingDuration),
            through: now
        )
        let todayRate = smoothedRate(
            in: currentSeries,
            from: calendar.startOfDay(for: now),
            through: now
        )

        var weightedRates: [(rate: Double, weight: Double)] = []
        if let recentRate {
            weightedRates.append((recentRate.rate, recentWeight))
        }
        if let todayRate {
            weightedRates.append((todayRate.rate, todayWeight))
        }

        let totalWeight = weightedRates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return nil
        }

        let blendedRate = weightedRates.reduce(0) { partial, item in
            partial + item.rate * item.weight
        } / totalWeight
        guard blendedRate.isFinite, blendedRate >= 0 else {
            return nil
        }

        let remainingPercentagePoints = max(0, 100 - latest.usedPercent)
        let exhaustionAt = blendedRate > 0
            ? now.addingTimeInterval(remainingPercentagePoints / blendedRate * 3600)
            : Date.distantFuture
        let confidence: UsageForecastConfidence = todayRate == nil ? .medium : .high

        return UsageForecast(
            ratePercentagePointsPerHour: blendedRate,
            exhaustionAt: exhaustionAt,
            resetAt: latest.resetAt,
            confidence: confidence,
            projection: linearProjection(
                startingAt: now,
                usedPercent: latest.usedPercent,
                rate: blendedRate,
                exhaustionAt: exhaustionAt,
                resetAt: latest.resetAt
            )
        )
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

        return UsageForecast(
            ratePercentagePointsPerHour: rate,
            exhaustionAt: latest.timestamp.addingTimeInterval(hoursUntilExhaustion * 3600),
            resetAt: latest.resetAt,
            confidence: .medium,
            projection: linearProjection(
                startingAt: latest.timestamp,
                usedPercent: latest.usedPercent,
                rate: rate,
                exhaustionAt: latest.timestamp.addingTimeInterval(hoursUntilExhaustion * 3600),
                resetAt: latest.resetAt
            )
        )
    }

    private static func linearProjection(
        startingAt start: Date,
        usedPercent: Double,
        rate: Double,
        exhaustionAt: Date,
        resetAt: Date
    ) -> [UsageForecastPoint] {
        let first = UsageForecastPoint(timestamp: start, usedPercent: usedPercent)
        let end = min(exhaustionAt, resetAt)
        guard end > start else {
            return [first]
        }

        let elapsedHours = end.timeIntervalSince(start) / 3600
        return [
            first,
            UsageForecastPoint(
                timestamp: end,
                usedPercent: usedPercent + max(0, rate) * elapsedHours
            )
        ]
    }

    private static func blendedProjection(
        historical: UsageForecast,
        currentUsedPercent: Double,
        targetRate: Double,
        scalarExhaustionAt: Date,
        now: Date
    ) -> (points: [UsageForecastPoint], exhaustionAt: Date) {
        guard !historical.projection.isEmpty,
              historical.ratePercentagePointsPerHour > 0,
              targetRate > 0
        else {
            return (
                linearProjection(
                    startingAt: now,
                    usedPercent: currentUsedPercent,
                    rate: targetRate,
                    exhaustionAt: scalarExhaustionAt,
                    resetAt: historical.resetAt
                ),
                scalarExhaustionAt
            )
        }

        let scale = targetRate / historical.ratePercentagePointsPerHour
        if abs(scale - 1) < 0.000_001 {
            return (historical.projection, historical.exhaustionAt)
        }

        let baseUsedPercent = historical.projection[0].usedPercent
        var points = [UsageForecastPoint(timestamp: now, usedPercent: currentUsedPercent)]

        for historicalPoint in historical.projection.dropFirst() {
            let scaledUsedPercent = currentUsedPercent
                + max(0, historicalPoint.usedPercent - baseUsedPercent) * scale
            if scaledUsedPercent >= 100, let previous = points.last {
                let delta = scaledUsedPercent - previous.usedPercent
                let fraction = delta > 0 ? (100 - previous.usedPercent) / delta : 0
                let duration = historicalPoint.timestamp.timeIntervalSince(previous.timestamp)
                let exhaustionAt = previous.timestamp.addingTimeInterval(duration * fraction)
                points.append(UsageForecastPoint(timestamp: exhaustionAt, usedPercent: 100))
                return (points, exhaustionAt)
            }

            points.append(UsageForecastPoint(
                timestamp: historicalPoint.timestamp,
                usedPercent: scaledUsedPercent
            ))
        }

        let projectionEnd = min(scalarExhaustionAt, historical.resetAt)
        if let last = points.last, projectionEnd > last.timestamp {
            let elapsedHours = projectionEnd.timeIntervalSince(now) / 3600
            points.append(UsageForecastPoint(
                timestamp: projectionEnd,
                usedPercent: currentUsedPercent + targetRate * elapsedHours
            ))
        }
        return (points, scalarExhaustionAt)
    }

    private static func smoothedRate(
        in samples: [UsageSample],
        from start: Date,
        through end: Date
    ) -> SmoothedRate? {
        let scoped = samples.filter { $0.timestamp >= start && $0.timestamp <= end }
        guard let first = scoped.first,
              let latest = scoped.last,
              scoped.count >= minimumSampleCount
        else {
            return nil
        }

        let duration = latest.timestamp.timeIntervalSince(first.timestamp)
        guard duration >= minimumSmoothedDuration else {
            return nil
        }

        let consumed = zip(scoped, scoped.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1.usedPercent - pair.0.usedPercent)
        }
        let rate = consumed / (duration / 3600)
        guard rate.isFinite, rate >= 0 else {
            return nil
        }

        return SmoothedRate(rate: rate, duration: duration)
    }

    private static func confidence(
        historicalRate: Double,
        recentRate: SmoothedRate?,
        todayRate: SmoothedRate?
    ) -> UsageForecastConfidence {
        guard let recentRate else {
            return .low
        }

        let disagreementThreshold = max(1, recentRate.rate * 2)
        if abs(historicalRate - recentRate.rate) > disagreementThreshold {
            return .low
        }

        if todayRate?.rate == 0 {
            return .medium
        }

        if recentRate.duration >= 2 * 24 * 60 * 60, todayRate != nil {
            return .high
        }

        return .medium
    }

    private struct SmoothedRate {
        let rate: Double
        let duration: TimeInterval
    }
}
