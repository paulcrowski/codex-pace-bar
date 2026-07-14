import Foundation

public enum UsageHistorySeries {
    public static let minimumScheduledResetAdvance: TimeInterval = 60 * 60

    public static func current(from samples: [UsageSample], now: Date) -> [UsageSample] {
        let chronologicalSamples = samples
            .filter { $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard chronologicalSamples.count > 1 else {
            return chronologicalSamples
        }

        var currentSeriesStart = chronologicalSamples.startIndex
        for index in chronologicalSamples.indices.dropFirst() {
            let previous = chronologicalSamples[chronologicalSamples.index(before: index)]
            let sample = chronologicalSamples[index]
            if startsNewSeries(previous: previous, sample: sample) {
                currentSeriesStart = index
            }
        }

        return Array(chronologicalSamples[currentSeriesStart...])
    }

    static func startsNewSeries(previous: UsageSample, sample: UsageSample) -> Bool {
        if sample.usedPercent < previous.usedPercent {
            return true
        }

        let resetAdvance = sample.resetAt.timeIntervalSince(previous.resetAt)
        return sample.timestamp >= previous.resetAt
            && resetAdvance >= minimumScheduledResetAdvance
    }
}
