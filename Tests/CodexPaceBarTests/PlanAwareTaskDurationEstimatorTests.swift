import CodexPaceBarCore
import Foundation
import Testing

struct PlanAwareTaskDurationEstimatorTests {
    @Test
    func exposesLearningStateWithoutInventingAPlanDuration() throws {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let features = CodexTaskPlanFeatures(
            stepCount: 2,
            workUnitCount: 2,
            verificationCount: 0,
            buildCount: 0,
            runtimeCheckCount: 0,
            repositoryCount: 0,
            plannedParallelism: 0,
            category: .smallFix,
            complexity: .simple
        )
        let plan = CodexTaskPlanSnapshot(taskID: "session:current", observedAt: now, features: features)
        let current = task("session", "current", startedAt: now.addingTimeInterval(-30), duration: nil)
        let history = (0..<3).map { index in
            task("session", "history-\(index)", startedAt: now.addingTimeInterval(-3_600 - Double(index)), duration: Double(60 + index), status: .completed)
        }
        var plans = Dictionary(uniqueKeysWithValues: history.map { ($0.id, CodexTaskPlanSnapshot(taskID: $0.id, observedAt: now, features: features)) })
        plans[plan.taskID] = plan

        let estimate = try #require(CodexPlanAwareTaskDurationEstimator().initialEstimate(
            for: current,
            plan: plan,
            now: now,
            history: history,
            plans: plans
        ))

        #expect(estimate.confidence == .learning)
        #expect(estimate.typicalTotal == nil)
        #expect(estimate.planUpperTotal == nil)
        #expect(estimate.sampleCount == 3)
    }

    @Test
    func estimatesInitialTotalAndConditionalSafeAwayForPersonalPlanCohort() throws {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let plan = CodexTaskPlanSnapshot(
            taskID: "session:current",
            observedAt: now.addingTimeInterval(-600),
            features: CodexTaskPlanFeatures(
                stepCount: 4,
                workUnitCount: 8,
                verificationCount: 2,
                buildCount: 1,
                runtimeCheckCount: 1,
                repositoryCount: 1,
                plannedParallelism: 0,
                category: .feature,
                complexity: .complex
            )
        )
        let current = task("session", "current", startedAt: now.addingTimeInterval(-600), duration: nil)
        let historical = (0..<12).map { index in
            task("session", "history-\(index)", startedAt: now.addingTimeInterval(-7_200 - Double(index)), duration: Double(1_200 + index * 60), status: .completed)
        }
        let plans = Dictionary(uniqueKeysWithValues: historical.enumerated().map { index, value in
            (value.id, CodexTaskPlanSnapshot(
                taskID: value.id,
                observedAt: value.completedAt ?? now,
                features: plan.features
            ))
        }.appending((plan.taskID, plan)))

        let estimate = try #require(CodexPlanAwareTaskDurationEstimator().initialEstimate(
            for: current,
            plan: plan,
            now: now,
            history: historical,
            plans: plans
        ))
        #expect(estimate.typicalTotal != nil)
        #expect(estimate.planUpperTotal ?? 0 >= estimate.typicalTotal ?? 0)
        #expect(estimate.sampleCount == 12)
        #expect(estimate.scope == .exact)
    }

    private func task(
        _ sessionID: String,
        _ turnID: String,
        startedAt: Date,
        duration: TimeInterval?,
        status: CodexTaskStatus = .working
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: sessionID,
            turnID: turnID,
            workingDirectory: "/work/project",
            model: "model",
            effort: "high",
            status: status,
            startedAt: startedAt,
            completedAt: duration.map { startedAt.addingTimeInterval($0) },
            duration: duration,
            timeToFirstToken: nil
        )
    }
}

private extension Array {
    func appending(_ element: Element) -> [Element] {
        var copy = self
        copy.append(element)
        return copy
    }
}
