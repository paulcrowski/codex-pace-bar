import Foundation

/// Estimates remaining active work for a native Codex goal.
/// Goal history is intentionally separate from turn history: one goal may span many turns.
public struct CodexGoalDurationEstimator: Sendable {
    public static let defaultMinimumSamples = 5
    public static let defaultHistoryLookbackDuration: TimeInterval = 45 * 24 * 60 * 60

    public let minimumSamples: Int
    public let historyLookbackDuration: TimeInterval
    public let upperPercentile: Double

    public init(
        minimumSamples: Int = Self.defaultMinimumSamples,
        historyLookbackDuration: TimeInterval = Self.defaultHistoryLookbackDuration,
        upperPercentile: Double = CodexTaskDurationEstimator.defaultUpperPercentile
    ) {
        self.minimumSamples = max(1, minimumSamples)
        self.historyLookbackDuration = max(0, historyLookbackDuration.isFinite ? historyLookbackDuration : Self.defaultHistoryLookbackDuration)
        self.upperPercentile = min(max(upperPercentile.isFinite ? upperPercentile : 0.85, 0.5), 1)
    }

    public func estimate(
        for current: CodexGoalActivity,
        now: Date,
        history: [CodexGoalActivity]
    ) -> CodexTaskDurationEstimate? {
        guard let cohort = cohort(for: current, now: now, history: history) else { return nil }
        let learned = cohort.values.count >= minimumSamples
        return CodexTaskDurationEstimate(
            medianRemaining: learned ? median(cohort.values) : nil,
            safeRemaining: learned ? percentile(upperPercentile, in: cohort.values) : nil,
            sampleCount: cohort.values.count,
            confidence: learned ? .learned : .learning,
            scope: cohort.scope
        )
    }

    public func completionForecast(
        for current: CodexGoalActivity,
        within horizon: TimeInterval,
        now: Date,
        history: [CodexGoalActivity]
    ) -> CodexTaskCompletionForecast? {
        guard horizon.isFinite, horizon >= 0,
              let cohort = cohort(for: current, now: now, history: history),
              cohort.values.count >= minimumSamples
        else { return nil }
        let count = cohort.values.count { $0 <= horizon }
        let probability = Double(count + 1) / Double(cohort.values.count + 2)
        return CodexTaskCompletionForecast(
            horizon: horizon,
            probability: probability,
            sampleCount: cohort.values.count,
            scope: cohort.scope
        )
    }

    private func cohort(
        for current: CodexGoalActivity,
        now: Date,
        history: [CodexGoalActivity]
    ) -> Cohort? {
        guard current.isActive, current.activeDuration.isFinite, current.activeDuration >= 0 else { return nil }
        let values = history.compactMap { goal -> (CodexGoalActivity, TimeInterval)? in
            guard goal.id != current.id,
                  goal.status == .complete,
                  goal.updatedAt <= now,
                  now.timeIntervalSince(goal.updatedAt) <= historyLookbackDuration,
                  goal.activeDuration.isFinite,
                  goal.activeDuration > current.activeDuration
            else { return nil }
            return (goal, goal.activeDuration - current.activeDuration)
        }
        let project = values.filter { matchesProject(current, $0.0) }.map(\.1).sorted()
        if !project.isEmpty {
            return Cohort(scope: .project, values: project)
        }
        let global = values.map(\.1).sorted()
        guard !global.isEmpty else { return nil }
        return Cohort(scope: .global, values: global)
    }

    private func matchesProject(_ current: CodexGoalActivity, _ historical: CodexGoalActivity) -> Bool {
        guard let project = current.workingDirectory else { return true }
        return historical.workingDirectory == project
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    private func percentile(_ value: Double, in values: [TimeInterval]) -> TimeInterval {
        let index = Int(ceil(value * Double(values.count - 1)))
        return values[min(max(index, 0), values.count - 1)]
    }

    private struct Cohort {
        let scope: CodexTaskDurationEstimateScope
        let values: [TimeInterval]
    }
}
