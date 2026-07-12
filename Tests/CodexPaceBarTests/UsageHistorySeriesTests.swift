import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct UsageHistorySeriesTests {
    @Test
    func firstSampleStartsCurrentSeries() {
        let now = date(1_000)
        let samples = [sample(at: now, used: 10, resetAt: date(10_000))]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func increasingUsageRemainsContinuous() {
        let now = date(3_000)
        let resetAt = date(10_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: resetAt),
            sample(at: date(2_000), used: 12, resetAt: resetAt),
            sample(at: now, used: 15, resetAt: resetAt)
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func unchangedUsageRemainsContinuous() {
        let now = date(3_000)
        let resetAt = date(10_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: resetAt),
            sample(at: date(2_000), used: 10, resetAt: resetAt),
            sample(at: now, used: 10, resetAt: resetAt)
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func resetTimestampJitterRemainsContinuous() {
        let now = date(3_000)
        let resetAt = date(10_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: resetAt),
            sample(at: date(2_000), used: 11, resetAt: resetAt.addingTimeInterval(30)),
            sample(at: now, used: 12, resetAt: resetAt.addingTimeInterval(52))
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func resetTimestampMovingBackwardRemainsContinuous() {
        let now = date(3_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: date(10_000)),
            sample(at: date(2_000), used: 11, resetAt: date(9_000)),
            sample(at: now, used: 12, resetAt: date(8_000))
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func largeResetCorrectionBeforeDeadlineRemainsContinuous() {
        let now = date(3_000)
        let oldReset = date(10_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: oldReset),
            sample(at: now, used: 12, resetAt: oldReset.addingTimeInterval(24 * 60 * 60))
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func subHourResetAdvanceAfterDeadlineRemainsContinuous() {
        let oldReset = date(10_000)
        let now = oldReset.addingTimeInterval(60)
        let samples = [
            sample(at: oldReset.addingTimeInterval(-60), used: 10, resetAt: oldReset),
            sample(at: now, used: 10, resetAt: oldReset.addingTimeInterval(3_599))
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func oneHourResetAdvanceAfterDeadlineStartsNewSeries() {
        let oldReset = date(10_000)
        let now = oldReset.addingTimeInterval(60)
        let latest = sample(at: now, used: 10, resetAt: oldReset.addingTimeInterval(3_600))
        let samples = [
            sample(at: oldReset.addingTimeInterval(-60), used: 10, resetAt: oldReset),
            latest
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == [latest])
    }

    @Test
    func lowerUsageStartsNewSeriesWithoutResetMetadataChange() {
        let now = date(3_000)
        let resetAt = date(10_000)
        let latest = sample(at: now, used: 5, resetAt: resetAt)
        let samples = [
            sample(at: date(1_000), used: 30, resetAt: resetAt),
            latest
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == [latest])
        #expect(samples.count == 2)
    }

    @Test
    func tinyUsageDecreaseStartsNewSeries() {
        let now = date(2_000)
        let resetAt = date(10_000)
        let latest = sample(at: now, used: 19.9, resetAt: resetAt)

        #expect(UsageHistorySeries.current(
            from: [sample(at: date(1_000), used: 20, resetAt: resetAt), latest],
            now: now
        ) == [latest])
    }

    @Test
    func manuallyTriggeredUsageResetBeforeAdvertisedDeadlineStartsNewSeries() {
        let now = date(2_000)
        let resetAt = date(100_000)
        let latest = sample(at: now, used: 2, resetAt: resetAt)

        #expect(UsageHistorySeries.current(
            from: [sample(at: date(1_000), used: 70, resetAt: resetAt), latest],
            now: now
        ) == [latest])
    }

    @Test
    func openAIScheduledResetStartsNewSeriesWhenUsageIsAlreadyHigher() {
        let oldReset = date(10_000)
        let newReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        let now = oldReset.addingTimeInterval(60)
        let latest = sample(at: now, used: 8, resetAt: newReset)
        let samples = [
            sample(at: oldReset.addingTimeInterval(-60), used: 5, resetAt: oldReset),
            latest
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == [latest])
    }

    @Test
    func openAIScheduledResetStartsNewSeriesWhenUsageIsUnchanged() {
        let oldReset = date(10_000)
        let newReset = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        let now = oldReset.addingTimeInterval(60)
        let latest = sample(at: now, used: 5, resetAt: newReset)

        #expect(UsageHistorySeries.current(
            from: [sample(at: oldReset.addingTimeInterval(-60), used: 5, resetAt: oldReset), latest],
            now: now
        ) == [latest])
    }

    @Test
    func sleepingAcrossMultipleWindowsStartsNewSeries() {
        let oldReset = date(10_000)
        let newReset = oldReset.addingTimeInterval(14 * 24 * 60 * 60)
        let now = oldReset.addingTimeInterval(7 * 24 * 60 * 60)
        let latest = sample(at: now, used: 12, resetAt: newReset)

        #expect(UsageHistorySeries.current(
            from: [sample(at: oldReset.addingTimeInterval(-60), used: 10, resetAt: oldReset), latest],
            now: now
        ) == [latest])
    }

    @Test
    func limitIdentifierCorrectionDoesNotSplitIncreasingUsage() {
        let now = date(2_000)
        let resetAt = date(10_000)
        let samples = [
            sample(at: date(1_000), used: 10, resetAt: resetAt, limitId: "rateLimits"),
            sample(at: now, used: 11, resetAt: resetAt, limitId: "codex")
        ]

        #expect(UsageHistorySeries.current(from: samples, now: now) == samples)
    }

    @Test
    func unsortedSamplesAreClassifiedChronologically() {
        let now = date(3_000)
        let resetAt = date(10_000)
        let first = sample(at: date(1_000), used: 70, resetAt: resetAt)
        let second = sample(at: date(2_000), used: 3, resetAt: resetAt)
        let third = sample(at: now, used: 4, resetAt: resetAt)

        #expect(UsageHistorySeries.current(from: [third, first, second], now: now) == [second, third])
    }

    @Test
    func futureSamplesDoNotInfluenceCurrentSeries() {
        let now = date(2_000)
        let resetAt = date(10_000)
        let current = sample(at: now, used: 10, resetAt: resetAt)
        let future = sample(at: date(3_000), used: 1, resetAt: resetAt)

        #expect(UsageHistorySeries.current(from: [current, future], now: now) == [current])
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(
        at timestamp: Date,
        used: Double,
        resetAt: Date,
        limitId: String = "codex"
    ) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: limitId)
    }
}
