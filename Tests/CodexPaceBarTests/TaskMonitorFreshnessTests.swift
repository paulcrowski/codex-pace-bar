import CodexPaceBarCore
import Foundation
import Testing

struct TaskMonitorFreshnessTests {
    @Test
    func ordinaryTurnExpiresAfterThirtyMinutes() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let task = activity(lastEventAt: now.addingTimeInterval(-30 * 60 - 1))

        #expect(
            !CodexTaskFreshnessPolicy().isFresh(
                task: task,
                now: now,
                activeGoalThreadIDs: []
            )
        )
    }

    @Test
    func activeGoalTurnKeepsItsLongWindow() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let task = activity(
            sessionID: "goal-session",
            lastEventAt: now.addingTimeInterval(-90 * 60)
        )

        #expect(
            CodexTaskFreshnessPolicy().isFresh(
                task: task,
                now: now,
                activeGoalThreadIDs: ["goal-session"]
            )
        )
    }

    @Test
    func activeGoalTurnAlsoExpiresAfterAggregateWindow() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let task = activity(
            sessionID: "goal-session",
            lastEventAt: now.addingTimeInterval(-2 * 60 * 60 - 1)
        )

        #expect(
            !CodexTaskFreshnessPolicy().isFresh(
                task: task,
                now: now,
                activeGoalThreadIDs: ["goal-session"]
            )
        )
    }

    private func activity(
        sessionID: String = "ordinary-session",
        lastEventAt: Date
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: sessionID,
            turnID: "turn",
            workingDirectory: "/work/project",
            model: nil,
            effort: nil,
            status: .working,
            startedAt: lastEventAt,
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil,
            lastEventAt: lastEventAt
        )
    }
}
