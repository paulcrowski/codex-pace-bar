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
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        let forecast = try #require(UsageForecaster.forecast(samples: samples, now: now))

        #expect(!forecast.willRunOutBeforeReset)
    }

    @Test
    func requiresAtLeastOneHourOfHistory() {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-30 * 60), used: 40, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
    }

    @Test
    func ignoresFlatUsage() {
        let now = Date(timeIntervalSince1970: 100_000)
        let resetAt = now.addingTimeInterval(20 * 60 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-2 * 60 * 60), used: 50, resetAt: resetAt),
            sample(at: now, used: 50, resetAt: resetAt)
        ]

        #expect(UsageForecaster.forecast(samples: samples, now: now) == nil)
    }

    private func sample(at timestamp: Date, used: Double, resetAt: Date) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: "codex")
    }
}
