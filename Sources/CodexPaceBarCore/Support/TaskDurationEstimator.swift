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

public struct CodexTaskDurationEstimator: Sendable {
    public let minimumSamples: Int

    public init(minimumSamples: Int = 10) {
        self.minimumSamples = max(1, minimumSamples)
    }

    public func estimate(
        for current: CodexTaskActivity,
        now: Date,
        history: [CodexTaskActivity]
    ) -> CodexTaskDurationEstimate? {
        guard current.status == .working || current.status == .queued else {
            return nil
        }
        let currentWaiting = current.waitingDuration
            + (current.waitingStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        let elapsed = max(0, current.startedAt.map { now.timeIntervalSince($0) } ?? 0) - currentWaiting
        let candidates = history.compactMap { historical -> (CodexTaskActivity, TimeInterval)? in
            guard historical.id != current.id,
                  historical.status == .completed,
                  let completedAt = historical.completedAt,
                  completedAt <= now,
                  let duration = historical.duration,
                  now.timeIntervalSince(completedAt) <= 90 * 24 * 60 * 60
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
        var selected: (CodexTaskDurationEstimateScope, [TimeInterval])?
        for tier in tiers {
            let values = candidates.filter { tier.1($0.0) }.map(\.1).sorted()
            guard !values.isEmpty else { continue }
            selected = (tier.0, values)
            if values.count >= minimumSamples { break }
        }

        guard let selected else {
            return nil
        }
        let remainingDurations = selected.1

        let confidence: CodexTaskDurationConfidence = remainingDurations.count >= minimumSamples
            ? .learned
            : .learning
        let median = confidence == .learned ? median(of: remainingDurations) : nil
        let safe = confidence == .learned ? percentile(0.8, in: remainingDurations) : nil

        return CodexTaskDurationEstimate(
            medianRemaining: median,
            safeRemaining: safe,
            sampleCount: remainingDurations.count,
            confidence: confidence,
            scope: selected.0
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
                  now.timeIntervalSince(completedAt) <= 30 * 24 * 60 * 60,
                  workingDirectory == nil || activity.workingDirectory == workingDirectory
            else { return nil }
            return max(0, duration - activity.waitingDuration)
        }.filter { $0 > 0 }.sorted()
        guard durations.count >= minimumSamples else { return nil }
        return CodexTaskDurationDistribution(
            median: median(of: durations),
            safe: percentile(0.8, in: durations),
            sampleCount: durations.count
        )
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
}
