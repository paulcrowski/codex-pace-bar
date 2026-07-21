import CodexPaceBarCore
import Foundation
import Testing

struct GoalDurationEstimatorTests {
    @Test
    func defaultsUseFiveSamplesAndFortyFiveDayHistory() {
        let estimator = CodexGoalDurationEstimator()

        #expect(estimator.minimumSamples == 5)
        #expect(estimator.historyLookbackDuration == 45 * 24 * 60 * 60)
    }

    @Test
    func estimatesRemainingActiveTimeFromCompletedGoalsOnly() {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = goal(id: "current", created: 9_900, updated: 9_950, status: .active, active: 100)
        let history = [
            goal(id: "one", created: 8_000, updated: 8_200, status: .complete, active: 200),
            goal(id: "two", created: 7_000, updated: 7_300, status: .complete, active: 300),
            goal(id: "three", created: 6_000, updated: 6_400, status: .complete, active: 400),
            goal(id: "blocked", created: 5_000, updated: 5_500, status: .blocked, active: 500)
        ]

        let estimate = CodexGoalDurationEstimator(minimumSamples: 3).estimate(
            for: current,
            now: now,
            history: history
        )

        #expect(estimate?.confidence == .learned)
        #expect(estimate?.sampleCount == 3)
        #expect(estimate?.medianRemaining == 200)
        #expect(estimate?.safeRemaining == 300)
    }

    @Test
    func keepsSmallGoalHistoryInLearningState() {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = goal(id: "current", created: 9_900, updated: 9_950, status: .active, active: 100)
        let history = [goal(id: "one", created: 8_000, updated: 8_200, status: .complete, active: 200)]

        let estimate = CodexGoalDurationEstimator(minimumSamples: 3).estimate(
            for: current,
            now: now,
            history: history
        )

        #expect(estimate?.confidence == .learning)
        #expect(estimate?.medianRemaining == nil)
        #expect(estimate?.sampleCount == 1)
    }

    private func goal(
        id: String,
        created: TimeInterval,
        updated: TimeInterval,
        status: CodexGoalStatus,
        active: TimeInterval
    ) -> CodexGoalActivity {
        CodexGoalActivity(
            threadID: id,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            status: status,
            activeDuration: active,
            workingDirectory: "/work/project"
        )
    }
}
