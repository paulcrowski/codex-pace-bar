@testable import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct UsagePatternForecasterTests {
    @Test
    func historyModeUsesTheSameThirtyDayWindowAsPersistence() {
        #expect(UsageForecaster.historyLookbackDuration == 30 * day)
        #expect(UsageForecaster.historyLookbackDuration == UsageHistoryRepository.retentionDuration)
    }

    @Test
    func predictsExactExhaustionFromThirtyDaysOfHourlyPatterns() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(7 * day)
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 90,
            currentResetAt: resetAt
        ).reversed()

        let forecast = try #require(historyForecast(Array(samples), now: now))

        #expect(forecast.projection.last == UsageForecastPoint(
            timestamp: now.addingTimeInterval(5 * hour),
            usedPercent: 100
        ))
        #expect(forecast.exhaustionAt == now.addingTimeInterval(5 * hour))
        #expect(forecast.willRunOutBeforeReset)
    }

    @Test
    func samplesOlderThanThirtyDaysDoNotInfluencePrediction() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(8 * hour)
        var samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 80,
            currentResetAt: resetAt
        )
        let expiredStart = now.addingTimeInterval(-35 * day + 6 * hour)
        samples.append(sample(at: expiredStart, used: 0, resetAt: expiredStart.addingTimeInterval(7 * day)))
        samples.append(sample(at: expiredStart.addingTimeInterval(hour), used: 90, resetAt: expiredStart.addingTimeInterval(7 * day)))

        let forecast = try #require(historyForecast(samples, now: now))

        let projected = try #require(forecast.projection.last)
        #expect(abs(projected.usedPercent - 92) < 0.000_001)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func givesRecentWeeksMoreWeight() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(hour)
        var samples: [UsageSample] = []
        for (weeksAgo, rate) in [(4, 1.0), (3, 1.0), (2, 1.0), (1, 4.0)] {
            samples += repeatingPattern(
                now: now,
                weeksAgo: [weeksAgo],
                startOffsetHours: 0,
                hourlyRates: Array(repeating: rate, count: 6),
                currentUsed: nil,
                currentResetAt: resetAt
            )
        }
        samples.append(sample(at: now, used: 20, resetAt: resetAt))

        let forecast = try #require(historyForecast(samples, now: now))

        let projected = try #require(forecast.projection.last)
        #expect(abs(projected.usedPercent - 22.2) < 0.000_001)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func projectionPreservesRecurringNightAndWeekendPauses() throws {
        let now = date("2026-07-17T20:00:00Z")
        let resetAt = now.addingTimeInterval(62 * hour)
        var hourlyRates = Array(repeating: 0.0, count: 62)
        hourlyRates[0] = 2
        hourlyRates[1] = 2
        hourlyRates[60] = 3
        hourlyRates[61] = 3
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: hourlyRates,
            currentUsed: 10,
            currentResetAt: resetAt
        )

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection.count == 63)
        #expect(forecast.projection[2] == UsageForecastPoint(
            timestamp: now.addingTimeInterval(2 * hour),
            usedPercent: 14
        ))
        #expect(forecast.projection[60] == UsageForecastPoint(
            timestamp: now.addingTimeInterval(60 * hour),
            usedPercent: 14
        ))
        #expect(forecast.projection.last == UsageForecastPoint(
            timestamp: resetAt,
            usedPercent: 20
        ))
    }

    @Test
    func averagesWorkdaysByHourAndKeepsWeekendSeparate() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(7 * day)
        let oldStart = now.addingTimeInterval(-8 * day)
        let oldReset = oldStart.addingTimeInterval(7 * day)
        var samples = [
            sample(at: oldStart, used: 0, resetAt: oldReset),
            sample(at: oldStart.addingTimeInterval(4 * hour), used: 0, resetAt: oldReset)
        ]

        for (daysAgo, rate) in [(6, 1.0), (5, 3.0), (4, 1.0), (3, 3.0), (2, 0.0), (1, 0.0)] {
            let start = now.addingTimeInterval(-TimeInterval(daysAgo) * day)
            let historicalReset = start.addingTimeInterval(7 * day)
            samples += [
                sample(at: start, used: 0, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(hour), used: rate, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(2 * hour), used: rate, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(3 * hour), used: rate, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(4 * hour), used: rate, resetAt: historicalReset)
            ]
        }
        samples.append(sample(at: now, used: 10, resetAt: resetAt))

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection[1] == UsageForecastPoint(
            timestamp: now.addingTimeInterval(hour),
            usedPercent: 12
        ))
        let saturdayMorning = try #require(forecast.projection.first {
            $0.timestamp == now.addingTimeInterval(5 * day + hour)
        })
        #expect(saturdayMorning.usedPercent == 20)
    }

    @Test
    func projectionStopsAtExactMidHourExhaustion() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(7 * day)
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 91,
            currentResetAt: resetAt
        )

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection.last == UsageForecastPoint(
            timestamp: now.addingTimeInterval(4.5 * hour),
            usedPercent: 100
        ))
        #expect(forecast.exhaustionAt == now.addingTimeInterval(4.5 * hour))
    }

    @Test
    func scheduledResetWithHigherUsageIsNotLearnedAsConsumption() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(8 * hour)
        var samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: nil,
            currentResetAt: resetAt
        )
        let resetWeekStart = now.addingTimeInterval(-7 * day)
        let oldReset = resetWeekStart.addingTimeInterval(6 * hour + 15 * 60)
        samples = samples.map { existing in
            guard existing.timestamp == resetWeekStart.addingTimeInterval(6 * hour) else {
                return existing
            }
            return sample(at: existing.timestamp, used: existing.usedPercent, resetAt: oldReset)
        }
        samples.append(sample(
            at: resetWeekStart.addingTimeInterval(6 * hour + 30 * 60),
            used: 80,
            resetAt: oldReset.addingTimeInterval(7 * day)
        ))
        samples.append(sample(at: now, used: 80, resetAt: resetAt))

        let forecast = try #require(historyForecast(samples, now: now))

        let projected = try #require(forecast.projection.last)
        #expect(abs(projected.usedPercent - 92) < 0.000_001)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func usageAfterCorrectionStillContributesToPattern() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(7 * hour)
        var samples: [UsageSample] = []

        for weeksAgo in [4, 3, 2, 1] {
            let start = now.addingTimeInterval(-TimeInterval(weeksAgo) * 7 * day)
            let historicalReset = start.addingTimeInterval(7 * day)
            samples += [
                sample(at: start, used: 0, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(hour), used: 2, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(2 * hour), used: 4, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(3 * hour), used: 1, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(4 * hour), used: 3, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(5 * hour), used: 5, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(6 * hour), used: 7, resetAt: historicalReset),
                sample(at: start.addingTimeInterval(7 * hour), used: 9, resetAt: historicalReset)
            ]
        }
        samples.append(sample(at: now, used: 90, resetAt: resetAt))

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection.last?.usedPercent == 100)
        #expect(forecast.exhaustionAt == now.addingTimeInterval(6 * hour))
        #expect(forecast.willRunOutBeforeReset)
    }

    @Test
    func longUnobservedUsageGapIsNotSpreadAcrossWorkingHours() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(10 * hour)
        var samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: nil,
            currentResetAt: resetAt
        )
        let recentStart = now.addingTimeInterval(-7 * day)
        samples.append(sample(
            at: recentStart.addingTimeInterval(9 * hour),
            used: 90,
            resetAt: recentStart.addingTimeInterval(7 * day)
        ))
        samples.append(sample(at: now, used: 80, resetAt: resetAt))

        let forecast = try #require(historyForecast(samples, now: now))

        let projected = try #require(forecast.projection.last)
        #expect(abs(projected.usedPercent - 92) < 0.000_001)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func fallsBackToRecentPaceUntilHistoricalEvidenceIsSufficient() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(20 * hour)
        let samples = [
            sample(at: now.addingTimeInterval(-2 * hour), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-hour), used: 45, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection == [
            UsageForecastPoint(timestamp: now, usedPercent: 50),
            UsageForecastPoint(timestamp: now.addingTimeInterval(10 * hour), usedPercent: 100)
        ])
        #expect(forecast.exhaustionAt == now.addingTimeInterval(10 * hour))
    }

    @Test
    func validPatternWithNoExpectedUsageBeforeResetDoesNotUseRecentFallback() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(6 * hour)
        var samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 12,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: nil,
            currentResetAt: resetAt
        )
        samples += [
            sample(at: now.addingTimeInterval(-2 * hour), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-hour), used: 45, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection.allSatisfy { $0.usedPercent == 50 })
        #expect(forecast.projection.last?.timestamp == resetAt)
        #expect(forecast.exhaustionAt == .distantFuture)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func recentPaceModePreservesCurrentForecastBehavior() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(20 * hour)
        var samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: nil,
            currentResetAt: resetAt
        )
        samples += [
            sample(at: now.addingTimeInterval(-2 * hour), used: 80, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-hour), used: 85, resetAt: resetAt),
            sample(at: now, used: 90, resetAt: resetAt)
        ]

        let recent = try #require(UsageForecaster.forecast(
            samples: samples,
            now: now,
            mode: .recentPace,
            calendar: utcCalendar
        ))
        let historical = try #require(historyForecast(samples, now: now))

        #expect(recent.projection.count == 2)
        #expect(recent.exhaustionAt == now.addingTimeInterval(2 * hour))
        #expect(historical.exhaustionAt == now.addingTimeInterval(5 * hour))
    }

    @Test
    func exhaustionExactlyAtResetIsNotReportedAsEarly() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(6 * hour)
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 88,
            currentResetAt: resetAt
        )

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.exhaustionAt == resetAt)
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func alreadyExhaustedLimitProducesImmediateForecast() throws {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(6 * hour)
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 100,
            currentResetAt: resetAt
        )

        let forecast = try #require(historyForecast(samples, now: now))

        #expect(forecast.projection == [UsageForecastPoint(timestamp: now, usedPercent: 100)])
        #expect(forecast.exhaustionAt == now)
    }

    @Test
    func expiredResetDoesNotProduceHistoricalOrRecentForecast() {
        let now = date("2026-07-13T09:00:00Z")
        let samples = repeatingPattern(
            now: now,
            weeksAgo: [4, 3, 2, 1],
            startOffsetHours: 0,
            hourlyRates: Array(repeating: 2, count: 6),
            currentUsed: 90,
            currentResetAt: now
        )

        #expect(historyForecast(samples, now: now) == nil)
    }

    @Test
    func returnsNilWhenNeitherHistoricalNorRecentEvidenceIsUsable() {
        let now = date("2026-07-13T09:00:00Z")
        let resetAt = now.addingTimeInterval(6 * hour)
        let samples = [
            sample(at: now.addingTimeInterval(-28 * day), used: 10, resetAt: resetAt),
            sample(at: now, used: 30, resetAt: resetAt)
        ]

        #expect(historyForecast(samples, now: now) == nil)
    }

    private let day: TimeInterval = 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func historyForecast(_ samples: [UsageSample], now: Date) -> UsageForecast? {
        UsageForecaster.forecast(
            samples: samples,
            now: now,
            mode: .historyBased,
            calendar: utcCalendar
        )
    }

    private func repeatingPattern(
        now: Date,
        weeksAgo: [Int],
        startOffsetHours: Int,
        hourlyRates: [Double],
        currentUsed: Double?,
        currentResetAt: Date
    ) -> [UsageSample] {
        var samples: [UsageSample] = []
        for weeksAgo in weeksAgo {
            let start = now.addingTimeInterval(
                -TimeInterval(weeksAgo) * 7 * day + TimeInterval(startOffsetHours) * hour
            )
            let resetAt = start.addingTimeInterval(7 * day)
            var used = 0.0
            samples.append(sample(at: start, used: used, resetAt: resetAt))

            for (index, rate) in hourlyRates.enumerated() {
                used += rate
                samples.append(sample(
                    at: start.addingTimeInterval(TimeInterval(index + 1) * hour),
                    used: used,
                    resetAt: resetAt
                ))
            }
        }

        if let currentUsed {
            samples.append(sample(at: now, used: currentUsed, resetAt: currentResetAt))
        }
        return samples
    }

    private func sample(
        at timestamp: Date,
        used: Double,
        resetAt: Date,
        limitId: String = "codex"
    ) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: limitId)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
