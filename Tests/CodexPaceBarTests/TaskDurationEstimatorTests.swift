import CodexPaceBarCore
import Foundation
import Testing

struct TaskDurationEstimatorTests {
    @Test
    func doesNotEstimateAQueuedPlaceholderThatNeverStarted() {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let placeholder = CodexTaskActivity(
            sessionID: "session",
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

        #expect(CodexTaskDurationEstimator().estimate(
            for: placeholder,
            now: now,
            history: []
        ) == nil)
    }

    @Test
    func fallsBackFromExactMatchToProjectHistoryAndBuildsTypicalDistribution() throws {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let current = activity(sessionID: "current", turnID: "current", startedAt: now.addingTimeInterval(-60), duration: nil, model: "new-model")
        let history = (0..<12).map { index in
            activity(
                sessionID: "history-\(index)",
                turnID: "history-\(index)",
                startedAt: now.addingTimeInterval(-3600 - Double(index)),
                duration: TimeInterval(600 + index * 60),
                status: .completed,
                model: "old-model"
            )
        }
        let estimator = CodexTaskDurationEstimator(minimumSamples: 10)

        let estimate = try #require(estimator.estimate(for: current, now: now, history: history))
        #expect(estimate.scope == .project)
        #expect(estimate.confidence == .learned)
        #expect(estimator.distribution(history: history, now: now)?.sampleCount == 12)
    }

    @Test
    func estimatesRemainingP50AndCalibratedUpperBoundForSimilarLongerTasks() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-600),
            duration: nil
        )
        let history = (20...31).map { minutes -> CodexTaskActivity in
            let duration = Double(minutes * 60)
            return activity(
                sessionID: "history-\(minutes)",
                turnID: "turn-\(minutes)",
                startedAt: now.addingTimeInterval(-duration),
                duration: duration,
                status: .completed
            )
        }

        let estimate = CodexTaskDurationEstimator().estimate(
            for: current,
            now: now,
            history: history
        )

        #expect(estimate?.sampleCount == 12)
        #expect(estimate?.medianRemaining == 930)
        #expect(estimate?.safeRemaining == 1_200)
        #expect(estimate?.confidence == .learned)
    }

    @Test
    func estimatesSmoothedCompletionProbabilityWithinSelectedHorizon() throws {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-600),
            duration: nil
        )
        let history = (20...31).map { minutes -> CodexTaskActivity in
            let duration = Double(minutes * 60)
            return activity(
                sessionID: "history-\(minutes)",
                turnID: "turn-\(minutes)",
                startedAt: now.addingTimeInterval(-duration),
                duration: duration,
                status: .completed
            )
        }

        let forecast = try #require(CodexTaskDurationEstimator().completionForecast(
            for: current,
            within: 15 * 60,
            now: now,
            history: history
        ))

        #expect(forecast.horizon == 15 * 60)
        #expect(forecast.probability == 0.5)
        #expect(forecast.sampleCount == 12)
        #expect(forecast.scope == .exact)

        let broadForecast = try #require(CodexTaskDurationEstimator().completionForecast(
            for: current,
            within: 30 * 60,
            now: now,
            history: history
        ))
        #expect(broadForecast.probability == 13.0 / 14.0)
    }

    @Test
    func completionForecastRejectsInvalidHorizonAndSparseHistory() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-60),
            duration: nil
        )
        let history = (0..<3).map { index in
            activity(
                sessionID: "history-\(index)",
                turnID: "turn-\(index)",
                startedAt: now.addingTimeInterval(-1_200),
                duration: 1_200,
                status: .completed
            )
        }
        let estimator = CodexTaskDurationEstimator(minimumSamples: 10)

        #expect(estimator.completionForecast(
            for: current,
            within: -1,
            now: now,
            history: history
        ) == nil)
        #expect(estimator.completionForecast(
            for: current,
            within: 30 * 60,
            now: now,
            history: history
        ) == nil)
    }

    @Test
    func excludesCompletedTasksOutsideRetainedHistoryWindow() throws {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-60),
            duration: nil
        )
        let recent = (0..<9).map { index in
            activity(
                sessionID: "recent-\(index)",
                turnID: "recent-\(index)",
                startedAt: now.addingTimeInterval(-1_200 - Double(index)),
                duration: 1_200,
                status: .completed
            )
        }
        let old = (0..<10).map { index in
            activity(
                sessionID: "old-\(index)",
                turnID: "old-\(index)",
                startedAt: now.addingTimeInterval(-31 * 24 * 60 * 60 - 1_200 - Double(index)),
                duration: 1_200,
                status: .completed
            )
        }
        let estimator = CodexTaskDurationEstimator(minimumSamples: 10)

        let estimate = try #require(estimator.estimate(
            for: current,
            now: now,
            history: recent + old
        ))

        #expect(estimate.sampleCount == 9)
        #expect(estimate.confidence == .learning)
        #expect(estimator.completionForecast(
            for: current,
            within: 30 * 60,
            now: now,
            history: recent + old
        ) == nil)
    }

    @Test
    func waitsForMinimumHistoryBeforeShowingAConfidentEstimate() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-600),
            duration: nil
        )
        let history = (0..<3).map { index -> CodexTaskActivity in
            let minutes = 20 + index
            let duration = Double(minutes * 60)
            return activity(
                sessionID: "history-\(index)",
                turnID: "turn-\(index)",
                startedAt: now.addingTimeInterval(-duration),
                duration: duration,
                status: .completed
            )
        }

        let estimate = CodexTaskDurationEstimator(minimumSamples: 10).estimate(
            for: current,
            now: now,
            history: history
        )

        #expect(estimate?.sampleCount == 3)
        #expect(estimate?.confidence == .learning)
        #expect(estimate?.medianRemaining == nil)
        #expect(estimate?.safeRemaining == nil)
    }

    @Test
    func excludesShorterDifferentAndIncompleteTasks() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-1_200),
            duration: nil,
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high"
        )
        let matching = (0..<10).map { index -> CodexTaskActivity in
            let minutes = 25 + index
            let duration = Double(minutes * 60)
            return activity(
                sessionID: "matching-\(index)",
                turnID: "turn-\(index)",
                startedAt: now.addingTimeInterval(-duration),
                duration: duration,
                status: .completed,
                workingDirectory: "/work/project",
                model: "gpt-5.6",
                effort: "high"
            )
        }
        let shorter = activity(
            sessionID: "short",
            turnID: "short",
            startedAt: now.addingTimeInterval(-600),
            duration: 600,
            status: .completed,
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high"
        )
        let differentModel = activity(
            sessionID: "different",
            turnID: "different",
            startedAt: now.addingTimeInterval(-3_600),
            duration: 3_600,
            status: .completed,
            workingDirectory: "/work/project",
            model: "other-model",
            effort: "high"
        )
        let incomplete = activity(
            sessionID: "incomplete",
            turnID: "incomplete",
            startedAt: now.addingTimeInterval(-3_600),
            duration: 3_600,
            status: .working,
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high"
        )

        let estimate = CodexTaskDurationEstimator().estimate(
            for: current,
            now: now,
            history: matching + [shorter, differentModel, incomplete]
        )

        #expect(estimate?.sampleCount == 10)
        #expect(estimate?.confidence == .learned)
    }

    @Test
    func excludesFutureCompletedTasks() {
        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let current = activity(
            sessionID: "current",
            turnID: "current-turn",
            startedAt: now.addingTimeInterval(-600),
            duration: nil
        )
        let future = activity(
            sessionID: "future",
            turnID: "future-turn",
            startedAt: now.addingTimeInterval(60),
            duration: 1_200,
            status: .completed
        )

        let estimate = CodexTaskDurationEstimator(minimumSamples: 1).estimate(
            for: current,
            now: now,
            history: [future]
        )

        #expect(estimate == nil)
    }

    private func activity(
        sessionID: String,
        turnID: String,
        startedAt: Date,
        duration: TimeInterval?,
        status: CodexTaskStatus = .working,
        workingDirectory: String? = "/work/project",
        model: String? = "gpt-5.6",
        effort: String? = "high"
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: sessionID,
            turnID: turnID,
            workingDirectory: workingDirectory,
            model: model,
            effort: effort,
            status: status,
            startedAt: startedAt,
            completedAt: duration.map { startedAt.addingTimeInterval($0) },
            duration: duration,
            timeToFirstToken: nil
        )
    }
}
