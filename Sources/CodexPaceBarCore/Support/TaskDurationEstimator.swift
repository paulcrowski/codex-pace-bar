import Foundation

public enum CodexTaskDurationConfidence: String, Equatable, Sendable {
    case learning
    case learned
}

public enum CodexTaskDurationEstimateScope: String, Equatable, Sendable {
    case exact
    case project
    case global
}

public struct CodexTaskDurationEstimate: Equatable, Sendable {
    public let medianRemaining: TimeInterval?
    public let safeRemaining: TimeInterval?
    public let sampleCount: Int
    public let confidence: CodexTaskDurationConfidence
    public let scope: CodexTaskDurationEstimateScope

    public init(
        medianRemaining: TimeInterval?,
        safeRemaining: TimeInterval?,
        sampleCount: Int,
        confidence: CodexTaskDurationConfidence,
        scope: CodexTaskDurationEstimateScope = .exact
    ) {
        self.medianRemaining = medianRemaining
        self.safeRemaining = safeRemaining
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.scope = scope
    }
}

public struct CodexTaskDurationDistribution: Equatable, Sendable {
    public let median: TimeInterval
    public let safe: TimeInterval
    public let sampleCount: Int

    public init(median: TimeInterval, safe: TimeInterval, sampleCount: Int) {
        self.median = median
        self.safe = safe
        self.sampleCount = sampleCount
    }
}

public struct CodexTaskCompletionForecast: Equatable, Sendable {
    public let horizon: TimeInterval
    public let probability: Double
    public let sampleCount: Int
    public let scope: CodexTaskDurationEstimateScope

    public init(
        horizon: TimeInterval,
        probability: Double,
        sampleCount: Int,
        scope: CodexTaskDurationEstimateScope
    ) {
        self.horizon = horizon
        self.probability = probability
        self.sampleCount = sampleCount
        self.scope = scope
    }
}

public struct CodexTaskDurationEstimator: Sendable {
    public static let defaultHistoryLookbackDuration: TimeInterval = 30 * 24 * 60 * 60
    /// A slightly conservative empirical quantile used to keep the displayed upper estimate
    /// close to 80% observed walk-forward coverage when a raw P80 under-covers.
    public static let defaultUpperPercentile = 0.85

    public let minimumSamples: Int
    public let historyLookbackDuration: TimeInterval
    public let upperPercentile: Double

    public init(
        minimumSamples: Int = 10,
        historyLookbackDuration: TimeInterval = Self.defaultHistoryLookbackDuration,
        upperPercentile: Double = Self.defaultUpperPercentile
    ) {
        self.minimumSamples = max(1, minimumSamples)
        self.historyLookbackDuration = historyLookbackDuration.isFinite
            ? max(0, historyLookbackDuration)
            : Self.defaultHistoryLookbackDuration
        self.upperPercentile = upperPercentile.isFinite
            ? min(max(upperPercentile, 0.5), 1)
            : Self.defaultUpperPercentile
    }

    public func estimate(
        for current: CodexTaskActivity,
        now: Date,
        history: [CodexTaskActivity]
    ) -> CodexTaskDurationEstimate? {
        guard let cohort = remainingCohort(for: current, now: now, history: history) else {
            return nil
        }
        let remainingDurations = cohort.values

        let confidence: CodexTaskDurationConfidence = remainingDurations.count >= minimumSamples
            ? .learned
            : .learning
        let median = confidence == .learned ? median(of: remainingDurations) : nil
        let safe = confidence == .learned ? percentile(upperPercentile, in: remainingDurations) : nil

        return CodexTaskDurationEstimate(
            medianRemaining: median,
            safeRemaining: safe,
            sampleCount: remainingDurations.count,
            confidence: confidence,
            scope: cohort.scope
        )
    }

    public func completionForecast(
        for current: CodexTaskActivity,
        within horizon: TimeInterval,
        now: Date,
        history: [CodexTaskActivity]
    ) -> CodexTaskCompletionForecast? {
        guard horizon.isFinite,
              horizon >= 0,
              let cohort = remainingCohort(for: current, now: now, history: history),
              cohort.values.count >= minimumSamples
        else {
            return nil
        }
        let completedWithinHorizon = cohort.values.count { $0 <= horizon }
        // Laplace smoothing avoids claiming 0% or 100% from a small local sample.
        let probability = Double(completedWithinHorizon + 1) / Double(cohort.values.count + 2)
        return CodexTaskCompletionForecast(
            horizon: horizon,
            probability: probability,
            sampleCount: cohort.values.count,
            scope: cohort.scope
        )
    }

    public func distribution(
        history: [CodexTaskActivity],
        now: Date,
        workingDirectory: String? = nil
    ) -> CodexTaskDurationDistribution? {
        let durations = history.compactMap { activity -> TimeInterval? in
            guard activity.status == .completed,
                  let completedAt = activity.completedAt,
                  completedAt <= now,
                  let duration = activity.duration,
                  duration.isFinite,
                  activity.waitingDuration.isFinite,
                  activity.waitingDuration >= 0,
                  now.timeIntervalSince(completedAt) <= historyLookbackDuration,
                  workingDirectory == nil || activity.workingDirectory == workingDirectory
            else { return nil }
            return max(0, duration - activity.waitingDuration)
        }.filter { $0 > 0 }.sorted()
        guard durations.count >= minimumSamples else { return nil }
        return CodexTaskDurationDistribution(
            median: median(of: durations),
            safe: percentile(upperPercentile, in: durations),
            sampleCount: durations.count
        )
    }

    private func remainingCohort(
        for current: CodexTaskActivity,
        now: Date,
        history: [CodexTaskActivity]
    ) -> RemainingCohort? {
        guard current.isRunning,
              current.waitingDuration.isFinite,
              current.waitingDuration >= 0
        else {
            return nil
        }
        let openWaiting = current.waitingStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let rawElapsed = current.startedAt.map { now.timeIntervalSince($0) } ?? 0
        guard openWaiting.isFinite, rawElapsed.isFinite else { return nil }
        let elapsed = max(0, rawElapsed - current.waitingDuration - openWaiting)
        let candidates = history.compactMap { historical -> (CodexTaskActivity, TimeInterval)? in
            guard historical.id != current.id,
                  historical.status == .completed,
                  let completedAt = historical.completedAt,
                  completedAt <= now,
                  let duration = historical.duration,
                  duration.isFinite,
                  historical.waitingDuration.isFinite,
                  historical.waitingDuration >= 0,
                  now.timeIntervalSince(completedAt) <= historyLookbackDuration
            else {
                return nil
            }
            let activeDuration = max(0, duration - historical.waitingDuration)
            guard activeDuration > elapsed else { return nil }
            return (historical, activeDuration - elapsed)
        }

        let tiers: [(CodexTaskDurationEstimateScope, (CodexTaskActivity) -> Bool)] = [
            (.exact, { matchesExactly(current, $0) }),
            (.project, { matchesProject(current, $0) }),
            (.global, { _ in true })
        ]
        var selected: RemainingCohort?
        for tier in tiers {
            let values = candidates.filter { tier.1($0.0) }.map(\.1).sorted()
            guard !values.isEmpty else { continue }
            selected = RemainingCohort(scope: tier.0, values: values)
            if values.count >= minimumSamples { break }
        }
        return selected
    }

    private func matchesExactly(_ current: CodexTaskActivity, _ historical: CodexTaskActivity) -> Bool {
        guard matchesProject(current, historical) else { return false }
        if let model = current.model, historical.model != model { return false }
        if let effort = current.effort, historical.effort != effort { return false }
        return true
    }

    private func matchesProject(_ current: CodexTaskActivity, _ historical: CodexTaskActivity) -> Bool {
        if let workingDirectory = current.workingDirectory,
           historical.workingDirectory != workingDirectory {
            return false
        }
        return true
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private func percentile(_ percentile: Double, in values: [TimeInterval]) -> TimeInterval {
        let index = Int(ceil(percentile * Double(values.count - 1)))
        return values[min(max(index, 0), values.count - 1)]
    }

    private struct RemainingCohort {
        let scope: CodexTaskDurationEstimateScope
        let values: [TimeInterval]
    }
}
