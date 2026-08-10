import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct UsageForecasterTests {
    @Test
    func predictsExhaustionFromRecentUsageRate() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-2 * 60 * 60), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-60 * 60), used: 45, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace))

        #expect(forecast.ratePercentagePointsPerHour == 5)
        #expect(forecast.projection == [
            UsageForecastPoint(timestamp: now, usedPercent: 50),
            UsageForecastPoint(timestamp: now.addingTimeInterval(10 * 60 * 60), usedPercent: 100)
        ])
        #expect(forecast.hoursUntilExhaustion(at: now) == 10)
        #expect(forecast.willRunOutBeforeReset)
    }

    @Test
    func reportsWhenLimitShouldLastUntilReset() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(2 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-2 * 60 * 60), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-60 * 60), used: 45, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace))

        #expect(forecast.projection.last == UsageForecastPoint(timestamp: resetAt, usedPercent: 60))
        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func requiresAtLeastThreeSamples() {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-30 * 60), used: 40, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace) == nil)
    }

    @Test
    func requiresAtLeastThirtyMinutesOfHistory() {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-29 * 60), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-15 * 60), used: 45, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace) == nil)
    }

    @Test
    func requiresAtLeastOnePercentagePointOfChange() {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-60 * 60), used: 50, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-30 * 60), used: 50.4, resetAt: resetAt),
            sample(at: now, used: 50.9, resetAt: resetAt)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace) == nil)
    }

    @Test
    func forecastsAcrossMinorResetTimestampCorrections() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-60 * 60), used: 40, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-30 * 60), used: 45, resetAt: resetAt.addingTimeInterval(30)),
            sample(at: now, used: 50, resetAt: resetAt.addingTimeInterval(52))
        ]

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace))

        #expect(forecast.ratePercentagePointsPerHour == 10)
        #expect(forecast.resetAt == resetAt.addingTimeInterval(52))
    }

    @Test
    func preResetSamplesDoNotContributeToPostResetForecast() {
        let oldReset = Date(timeIntervalSince1970: 100_000)
        let now = oldReset.addingTimeInterval(60)
        let newReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        let samples = [
            sample(at: oldReset.addingTimeInterval(-2 * 60 * 60), used: 70, resetAt: oldReset),
            sample(at: oldReset.addingTimeInterval(-60 * 60), used: 80, resetAt: oldReset),
            sample(at: now, used: 8, resetAt: newReset)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace) == nil)
    }

    @Test
    func forecastUsesOnlyQualifyingPostResetSamples() throws {
        let oldReset = Date(timeIntervalSince1970: 100_000)
        let newReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        let now = oldReset.addingTimeInterval(61 * 60)
        let samples = [
            sample(at: oldReset.addingTimeInterval(-60 * 60), used: 80, resetAt: oldReset),
            sample(at: oldReset.addingTimeInterval(60), used: 3, resetAt: newReset),
            sample(at: oldReset.addingTimeInterval(31 * 60), used: 4, resetAt: newReset),
            sample(at: now, used: 5, resetAt: newReset)
        ]

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now, mode: .recentPace))

        #expect(forecast.ratePercentagePointsPerHour == 2)
        #expect(forecast.resetAt == newReset)
    }

    @Test
    func historyBasedForecastBlendsRecentThreeDayPace() throws {
        let now = date("2026-07-13T12:00:00Z")
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        var samples: [UsageSample] = []

        for weeksAgo in 1...4 {
            let start = now.addingTimeInterval(-TimeInterval(weeksAgo) * 7 * 24 * 60 * 60)
            let historicalReset = start.addingTimeInterval(7 * 24 * 60 * 60)
            samples.append(sample(at: start, used: 0, resetAt: historicalReset))
            for hour in 1...6 {
                samples.append(sample(
                    at: start.addingTimeInterval(TimeInterval(hour) * 60 * 60),
                    used: Double(hour * 2),
                    resetAt: historicalReset
                ))
            }
        }

        samples += [
            sample(at: now.addingTimeInterval(-72 * 60 * 60), used: 0, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-48 * 60 * 60), used: 4, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-24 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-6 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-3 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now, used: 8, resetAt: resetAt)
        ]

        let forecast = try #require(UsageForecaster.forecast(
            samples: samples,
            now: now,
            mode: .historyBased,
            calendar: utcCalendar
        ))

        #expect(forecast.ratePercentagePointsPerHour < 2)
        #expect(!forecast.willRunOutBeforeReset)
        #expect(forecast.confidence == .medium)
        #expect(forecast.projection.count > 2)
        #expect(zip(forecast.projection, forecast.projection.dropFirst()).contains { previous, next in
            next.timestamp > previous.timestamp && next.usedPercent == previous.usedPercent
        })
    }

    @Test
    func historyBasedFallbackUsesThreeDayPaceBeforeHistoryIsReady() throws {
        let now = date("2026-07-13T12:00:00Z")
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-72 * 60 * 60), used: 0, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-48 * 60 * 60), used: 4, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-24 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-6 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now.addingTimeInterval(-3 * 60 * 60), used: 8, resetAt: resetAt),
            sample(at: now, used: 8, resetAt: resetAt)
        ]

        let forecast = try #require(UsageForecaster.forecast(
            samples: samples,
            now: now,
            mode: .historyBased,
            calendar: utcCalendar
        ))

        #expect(forecast.ratePercentagePointsPerHour < 1)
        #expect(!forecast.willRunOutBeforeReset)
    }

    private func sample(at timestamp: Date, used: Double, resetAt: Date) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: "codex")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
