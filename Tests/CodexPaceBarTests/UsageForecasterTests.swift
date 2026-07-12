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

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now))

        #expect(forecast.ratePercentagePointsPerHour == 5)
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

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now))

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

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
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

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
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

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
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

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now))

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

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
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

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now))

        #expect(forecast.ratePercentagePointsPerHour == 2)
        #expect(forecast.resetAt == newReset)
    }

    private func sample(at timestamp: Date, used: Double, resetAt: Date) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: "codex")
    }
}
