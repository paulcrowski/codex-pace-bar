import Foundation

enum UsagePatternForecaster {
    static let minimumHistoryDuration: TimeInterval = 7 * 24 * 60 * 60
    static let minimumObservedDuration: TimeInterval = 24 * 60 * 60
    static let maximumObservationInterval: TimeInterval = 90 * 60

    static func forecast(
        samples: [UsageSample],
        now: Date,
        calendar: Calendar
    ) -> UsageForecast? {
        let cutoff = now.addingTimeInterval(-UsageForecaster.historyLookbackDuration)
        let samples = samples
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = samples.first,
              let latest = samples.last,
              latest.resetAt > now,
              latest.timestamp.timeIntervalSince(first.timestamp) >= minimumHistoryDuration
        else {
            return nil
        }

        var buckets: [HourBucket: BucketTotals] = [:]
        var observedDuration: TimeInterval = 0
        var observedUsage = 0.0

        for (previous, sample) in zip(samples, samples.dropFirst()) {
            let duration = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard duration > 0,
                  duration <= maximumObservationInterval,
                  !UsageHistorySeries.startsNewSeries(previous: previous, sample: sample)
            else {
                continue
            }

            let usage = sample.usedPercent - previous.usedPercent
            guard usage >= 0 else {
                continue
            }

            observedDuration += duration
            observedUsage += usage
            add(
                usage: usage,
                from: previous.timestamp,
                to: sample.timestamp,
                weight: recencyWeight(for: sample.timestamp, now: now),
                calendar: calendar,
                buckets: &buckets
            )
        }

        guard observedDuration >= minimumObservedDuration,
              observedUsage >= UsageForecaster.minimumUsageChange
        else {
            return nil
        }

        let rates = buckets.mapValues { totals in
            totals.observedHours > 0 ? totals.usage / totals.observedHours : 0
        }
        return projectedForecast(
            rates: rates,
            usedPercent: latest.usedPercent,
            now: now,
            resetAt: latest.resetAt,
            calendar: calendar
        )
    }

    private static func add(
        usage: Double,
        from start: Date,
        to end: Date,
        weight: Double,
        calendar: Calendar,
        buckets: inout [HourBucket: BucketTotals]
    ) {
        let duration = end.timeIntervalSince(start)
        var cursor = start

        while cursor < end {
            guard let hourInterval = calendar.dateInterval(of: .hour, for: cursor) else {
                return
            }
            let segmentEnd = min(end, hourInterval.end)
            let segmentDuration = segmentEnd.timeIntervalSince(cursor)
            let bucket = HourBucket(date: cursor, calendar: calendar)
            let weightedHours = segmentDuration / 3600 * weight
            let weightedUsage = usage * segmentDuration / duration * weight
            var totals = buckets[bucket, default: BucketTotals()]
            totals.observedHours += weightedHours
            totals.usage += weightedUsage
            buckets[bucket] = totals
            cursor = segmentEnd
        }
    }

    private static func projectedForecast(
        rates: [HourBucket: Double],
        usedPercent: Double,
        now: Date,
        resetAt: Date,
        calendar: Calendar
    ) -> UsageForecast {
        let initialRemaining = max(0, 100 - usedPercent)
        var projection = [UsageForecastPoint(timestamp: now, usedPercent: usedPercent)]
        guard initialRemaining > 0 else {
            return UsageForecast(
                projection: projection,
                exhaustionAt: now,
                resetAt: resetAt
            )
        }

        var remaining = initialRemaining
        var projectedUsedPercent = usedPercent
        var cursor = now

        while cursor < resetAt {
            guard let hourInterval = calendar.dateInterval(of: .hour, for: cursor) else {
                break
            }
            let segmentEnd = min(resetAt, hourInterval.end)
            let segmentHours = segmentEnd.timeIntervalSince(cursor) / 3600
            let rate = rates[HourBucket(date: cursor, calendar: calendar), default: 0]
            let segmentUsage = rate * segmentHours

            if rate > 0, segmentUsage >= remaining {
                let exhaustionAt = cursor.addingTimeInterval(remaining / rate * 3600)
                projection.append(UsageForecastPoint(timestamp: exhaustionAt, usedPercent: 100))
                return UsageForecast(
                    projection: projection,
                    exhaustionAt: exhaustionAt,
                    resetAt: resetAt
                )
            }

            remaining -= segmentUsage
            projectedUsedPercent += segmentUsage
            projection.append(UsageForecastPoint(
                timestamp: segmentEnd,
                usedPercent: projectedUsedPercent
            ))
            cursor = segmentEnd
        }

        return UsageForecast(
            projection: projection,
            exhaustionAt: .distantFuture,
            resetAt: resetAt
        )
    }

    private static func recencyWeight(for date: Date, now: Date) -> Double {
        let age = now.timeIntervalSince(date)
        return switch age {
        case ..<(7 * 24 * 60 * 60):
            4
        case ..<(14 * 24 * 60 * 60):
            3
        case ..<(21 * 24 * 60 * 60):
            2
        default:
            1
        }
    }

    private struct HourBucket: Hashable {
        let isWeekend: Bool
        let hour: Int

        init(date: Date, calendar: Calendar) {
            isWeekend = calendar.isDateInWeekend(date)
            hour = calendar.component(.hour, from: date)
        }
    }

    private struct BucketTotals {
        var usage = 0.0
        var observedHours = 0.0
    }
}
