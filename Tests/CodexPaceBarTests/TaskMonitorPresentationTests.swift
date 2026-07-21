import CodexPaceBarCore
import Foundation
import Testing

struct TaskMonitorPresentationTests {
    @Test
    func formatsThirtyMinuteCompletionChanceWithoutFalsePrecision() {
        let forecast = CodexTaskCompletionForecast(
            horizon: 30 * 60,
            probability: 13.0 / 14.0,
            sampleCount: 12,
            scope: .exact
        )

        #expect(
            CodexTaskCompletionForecastPresenter.text(forecast)
                == "30 min completion chance: 93%"
        )
    }

    @Test
    func distinguishesLegacyRunningTurnFromQueuedPlaceholder() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let legacyRunning = CodexTaskActivity(
            sessionID: "legacy",
            turnID: "turn",
            workingDirectory: "/work/project",
            model: nil,
            effort: nil,
            status: .queued,
            startedAt: now.addingTimeInterval(-60),
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil
        )
        let placeholder = CodexTaskActivity(
            sessionID: "placeholder",
            turnID: "turn",
            workingDirectory: "/work/project",
            model: nil,
            effort: nil,
            status: .queued,
            startedAt: nil,
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil
        )

        #expect(legacyRunning.isRunning)
        #expect(legacyRunning.visibleStatus == .working)
        #expect(!placeholder.isRunning)
        #expect(placeholder.visibleStatus == .queued)
    }

    @Test
    func showsNoActiveTasksWithoutInventingAnEta() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [],
            working: [],
            history: [],
            now: now,
            lastUpdatedAt: now
        )

        #expect(presentation.state == .noActiveTasks)
        #expect(presentation.title == "No active tasks")
        #expect(presentation.estimateText == nil)
        #expect(presentation.freshnessText == "Updated just now")
    }

    @Test
    func showsWaitingTaskBeforeWorkingTaskAndDoesNotShowAnEta() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let waiting = activity(
            sessionID: "waiting",
            turnID: "turn",
            status: .needsInput,
            startedAt: now.addingTimeInterval(-900),
            waitingStartedAt: now.addingTimeInterval(-120)
        )
        let working = activity(
            sessionID: "working",
            turnID: "turn",
            status: .working,
            startedAt: now.addingTimeInterval(-600)
        )

        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [waiting],
            working: [working],
            history: [],
            now: now,
            lastUpdatedAt: now
        )

        #expect(presentation.state == .needsYou(count: 2))
        #expect(presentation.title == "Needs you · 2 active")
        #expect(presentation.elapsedText == "Waiting 2 min")
        #expect(presentation.estimateText == nil)
        #expect(presentation.additionalTasksText == "+1 other active task")
    }

    @Test
    func showsLearnedEtaAsMedianToSafeRange() throws {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current",
            status: .working,
            startedAt: now.addingTimeInterval(-600)
        )
        let history = (20...31).map { minutes in
            let duration = Double(minutes * 60)
            return activity(
                sessionID: "history-\(minutes)",
                turnID: "turn-\(minutes)",
                status: .completed,
                startedAt: now.addingTimeInterval(-duration),
                duration: duration
            )
        }

        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [],
            working: [current],
            history: history,
            now: now,
            lastUpdatedAt: now
        )

        #expect(presentation.state == .working(count: 1))
        #expect(presentation.title == "Working · 1 active")
        #expect(presentation.projectName == "project")
        #expect(presentation.elapsedText == "10 min")
        #expect(presentation.estimateText == "ETA 16 min–20 min")
    }

    @Test
    func saysLearningUntilThereAreEnoughComparableTasks() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current",
            status: .working,
            startedAt: now.addingTimeInterval(-600)
        )
        let history = (0..<3).map { index in
            let duration = Double((20 + index) * 60)
            return activity(
                sessionID: "history-\(index)",
                turnID: "turn-\(index)",
                status: .completed,
                startedAt: now.addingTimeInterval(-duration),
                duration: duration
            )
        }

        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [],
            working: [current],
            history: history,
            now: now,
            lastUpdatedAt: now
        )

        #expect(presentation.estimateText == "Learning · 3/10 samples")
    }

    @Test
    func hidesInternalTurnIdentifierWhenProjectIsUnknown() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let task = CodexTaskActivity(
            sessionID: "session",
            turnID: "019f78ed-4da6-7fe0-b12a-8e92ebefd000",
            workingDirectory: nil,
            model: nil,
            effort: nil,
            status: .working,
            startedAt: now.addingTimeInterval(-60),
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil
        )

        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [],
            working: [task],
            history: [],
            now: now,
            lastUpdatedAt: now
        )

        #expect(presentation.projectName == "Codex task")
    }

    @Test
    func formatsStaleButKnownRefreshTimeClearly() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: [],
            working: [],
            history: [],
            now: now,
            lastUpdatedAt: now.addingTimeInterval(-125)
        )

        #expect(presentation.freshnessText == "Updated 2 min ago")
    }

    private func activity(
        sessionID: String,
        turnID: String,
        status: CodexTaskStatus,
        startedAt: Date,
        duration: TimeInterval? = nil,
        waitingStartedAt: Date? = nil
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: sessionID,
            turnID: turnID,
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high",
            status: status,
            startedAt: startedAt,
            completedAt: duration.map { startedAt.addingTimeInterval($0) },
            duration: duration,
            timeToFirstToken: nil,
            waitingStartedAt: waitingStartedAt
        )
    }
}
