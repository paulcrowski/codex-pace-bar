import Foundation

/// Estimates remaining wall-clock time for a native swarm parent task.
public struct CodexSwarmDurationEstimator: Sendable {
    public static let defaultHistoryLookbackDuration: TimeInterval = 30 * 24 * 60 * 60

    public let minimumSamples: Int
    public let historyLookbackDuration: TimeInterval
    public let upperPercentile: Double

    public init(
        minimumSamples: Int = 10,
        historyLookbackDuration: TimeInterval = Self.defaultHistoryLookbackDuration,
        upperPercentile: Double = CodexTaskDurationEstimator.defaultUpperPercentile
    ) {
        self.minimumSamples = max(1, minimumSamples)
        self.historyLookbackDuration = max(0, historyLookbackDuration.isFinite ? historyLookbackDuration : Self.defaultHistoryLookbackDuration)
        self.upperPercentile = min(max(upperPercentile.isFinite ? upperPercentile : 0.85, 0.5), 1)
    }

    public func estimate(
        for current: CodexSwarmActivity,
        now: Date,
        history: [CodexSwarmActivity]
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

    private func cohort(
        for current: CodexSwarmActivity,
        now: Date,
        history: [CodexSwarmActivity]
    ) -> Cohort? {
        let elapsed = max(0, now.timeIntervalSince(current.firstSpawnedAt))
        let values = history.compactMap { swarm -> (CodexSwarmActivity, TimeInterval)? in
            guard swarm.id != current.id,
                  let duration = swarm.duration,
                  duration.isFinite,
                  duration > elapsed,
                  swarm.completedAt.map({ now.timeIntervalSince($0) <= historyLookbackDuration }) == true
            else { return nil }
            return (swarm, duration - elapsed)
        }
        let project = values.filter { matchesProject(current, $0.0) }.map(\.1).sorted()
        if !project.isEmpty {
            return Cohort(scope: .project, values: project)
        }
        let global = values.map(\.1).sorted()
        guard !global.isEmpty else { return nil }
        return Cohort(scope: .global, values: global)
    }

    private func matchesProject(_ current: CodexSwarmActivity, _ historical: CodexSwarmActivity) -> Bool {
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
