import Foundation

public struct CodexPlanAwareTaskDurationEstimator: Sendable {
    public let minimumSamples: Int
    public let historyLookbackDuration: TimeInterval
    private let analyzer: CodexTaskDurationDistributionAnalyzer

    public init(
        minimumSamples: Int = 10,
        historyLookbackDuration: TimeInterval = 90 * 24 * 60 * 60
    ) {
        self.minimumSamples = max(1, minimumSamples)
        self.historyLookbackDuration = max(0, historyLookbackDuration)
        self.analyzer = CodexTaskDurationDistributionAnalyzer(minimumSamples: minimumSamples)
    }

    public func initialEstimate(
        for current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot?,
        now: Date,
        history: [CodexTaskActivity],
        plans: [String: CodexTaskPlanSnapshot]
    ) -> CodexPlanAwareTaskEstimate? {
        guard let plan,
              let cohort = cohort(for: current, plan: plan, now: now, history: history, plans: plans)
        else { return nil }
        let confidence: CodexTaskDurationConfidence = cohort.values.count >= minimumSamples ? .learned : .learning
        guard let model = analyzer.model(for: cohort.values) else {
            // Keep the plan visible while the personal cohort is learning,
            // but do not manufacture a duration from too few observations.
            return CodexPlanAwareTaskEstimate(
                typicalTotal: nil,
                planUpperTotal: nil,
                safeAwayRemaining: nil,
                model: .baseline,
                confidence: confidence,
                sampleCount: cohort.values.count,
                scope: cohort.scope,
                planSummary: plan.features.summary
            )
        }
        let safeAway = current.isRunning
            ? model.conditionalRemainingQuantile(0.2, elapsed: activeElapsed(for: current, now: now))
            : nil
        return CodexPlanAwareTaskEstimate(
            typicalTotal: model.quantile(0.5),
            planUpperTotal: model.quantile(0.85),
            safeAwayRemaining: safeAway,
            model: model.kind,
            confidence: confidence,
            sampleCount: cohort.values.count,
            scope: cohort.scope,
            planSummary: plan.features.summary
        )
    }

    public func estimate(
        for current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot?,
        now: Date,
        history: [CodexTaskActivity],
        plans: [String: CodexTaskPlanSnapshot]
    ) -> CodexTaskDurationEstimate? {
        guard let plan,
              current.isRunning,
              let cohort = cohort(for: current, plan: plan, now: now, history: history, plans: plans),
              let model = analyzer.model(for: cohort.values)
        else { return nil }
        let elapsed = activeElapsed(for: current, now: now)
        return CodexTaskDurationEstimate(
            medianRemaining: model.conditionalRemainingQuantile(0.5, elapsed: elapsed),
            safeRemaining: model.conditionalRemainingQuantile(0.85, elapsed: elapsed),
            sampleCount: cohort.values.count,
            confidence: cohort.values.count >= minimumSamples ? .learned : .learning,
            scope: cohort.scope
        )
    }

    public func completionForecast(
        for current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot?,
        within horizon: TimeInterval,
        now: Date,
        history: [CodexTaskActivity],
        plans: [String: CodexTaskPlanSnapshot]
    ) -> CodexTaskCompletionForecast? {
        guard let plan,
              current.isRunning,
              horizon.isFinite,
              horizon >= 0,
              let cohort = cohort(for: current, plan: plan, now: now, history: history, plans: plans),
              let model = analyzer.model(for: cohort.values),
              cohort.values.count >= minimumSamples
        else { return nil }
        return CodexTaskCompletionForecast(
            horizon: horizon,
            probability: model.conditionalCompletionProbability(
                elapsed: activeElapsed(for: current, now: now),
                horizon: horizon
            ),
            sampleCount: cohort.values.count,
            scope: cohort.scope
        )
    }

    public func distribution(
        history: [CodexTaskActivity],
        plans: [String: CodexTaskPlanSnapshot],
        now: Date
    ) -> CodexDurationDistributionStats? {
        let values = history.compactMap { activeDuration(for: $0, now: now, plan: plans[$0.id]) }
        return analyzer.stats(for: values)
    }

    private struct Cohort: Sendable {
        let scope: CodexTaskDurationEstimateScope
        let values: [TimeInterval]
    }

    private func cohort(
        for current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot,
        now: Date,
        history: [CodexTaskActivity],
        plans: [String: CodexTaskPlanSnapshot]
    ) -> Cohort? {
        let candidates = history.compactMap { task -> (CodexTaskActivity, CodexTaskPlanSnapshot, TimeInterval)? in
            guard task.id != current.id,
                  task.status == .completed,
                  let completedAt = task.completedAt,
                  completedAt <= now,
                  now.timeIntervalSince(completedAt) <= historyLookbackDuration,
                  let taskPlan = plans[task.id],
                  let duration = activeDuration(for: task, now: now, plan: taskPlan)
            else { return nil }
            return (task, taskPlan, duration)
        }
        let exactValues = candidates.filter {
            matchesExact(current, plan: plan, historical: $0.0, historicalPlan: $0.1)
        }.map { $0.2 }.sorted()
        if exactValues.count >= minimumSamples {
            return Cohort(scope: .exact, values: exactValues)
        }
        let projectValues = candidates.filter {
            matchesProject(current, plan: plan, historical: $0.0, historicalPlan: $0.1)
        }.map { $0.2 }.sorted()
        if projectValues.count >= minimumSamples {
            return Cohort(scope: .project, values: projectValues)
        }
        let globalValues = candidates.map { $0.2 }.sorted()
        guard !globalValues.isEmpty else { return nil }
        return Cohort(scope: .global, values: globalValues)
    }

    private func matchesExact(
        _ current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot,
        historical: CodexTaskActivity,
        historicalPlan: CodexTaskPlanSnapshot
    ) -> Bool {
        matchesProject(current, plan: plan, historical: historical, historicalPlan: historicalPlan)
            && (current.model == nil || current.model == historical.model)
            && (current.effort == nil || current.effort == historical.effort)
    }

    private func matchesProject(
        _ current: CodexTaskActivity,
        plan: CodexTaskPlanSnapshot,
        historical: CodexTaskActivity,
        historicalPlan: CodexTaskPlanSnapshot
    ) -> Bool {
        let sameProject = current.workingDirectory == nil || current.workingDirectory == historical.workingDirectory
        let sameCategory = plan.features.category == historicalPlan.features.category
        let sameComplexity = plan.features.complexity == historicalPlan.features.complexity
        return sameProject && sameCategory && sameComplexity
    }

    private func activeElapsed(for task: CodexTaskActivity, now: Date) -> TimeInterval {
        let raw = task.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let openWaiting = task.waitingStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, raw - task.waitingDuration - openWaiting)
    }

    private func activeDuration(
        for task: CodexTaskActivity,
        now: Date,
        plan: CodexTaskPlanSnapshot?
    ) -> TimeInterval? {
        guard plan != nil,
              let duration = task.duration,
              duration.isFinite,
              task.waitingDuration.isFinite,
              task.waitingDuration >= 0
        else { return nil }
        let active = max(0, duration - task.waitingDuration)
        return active > 2 ? active : nil
    }
}
