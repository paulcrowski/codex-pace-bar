import CodexPaceBarCore
import Foundation
import Testing

struct FocusLoadEstimatorTests {
    @Test
    func workRhythmUsesWordsAndCalibratesOnlyAfterEnoughRatedDays() {
        let now = Date()
        let checkIns = (0..<20).map { index in
            CodexDailyWorkCheckIn(
                day: now.addingTimeInterval(TimeInterval(-index * 86_400)),
                rating: index.isMultiple(of: 3) ? .tooMuch : .intense,
                rhythmScore: 60 + index % 10
            )
        }
        let estimate = CodexWorkRhythmEstimator().estimate(
            activities: [],
            checkIns: checkIns,
            now: now
        )
        #expect(estimate.level == .calm)
        #expect(estimate.isPersonallyCalibrated)
        #expect(estimate.detail == "Calm rhythm. This describes activity, not computer load.")
        #expect(!estimate.detail.contains("100"))
    }

    @Test
    func combinesShortBreaksButCountsLongBreakAsNewStreak() {
        let calendar = utcCalendar()
        let start = date("2026-07-18 09:00:00", calendar: calendar)
        let activities = [
            activity(id: "a", start: start, end: start.addingTimeInterval(60 * 60), status: .completed),
            activity(id: "b", start: start.addingTimeInterval(70 * 60), end: start.addingTimeInterval(130 * 60), status: .completed),
            activity(id: "c", start: start.addingTimeInterval(160 * 60), end: start.addingTimeInterval(220 * 60), status: .completed)
        ]

        let estimate = CodexFocusLoadEstimator(
            lookbackInterval: 6 * 60 * 60
        ).estimate(
            activities: activities,
            now: start.addingTimeInterval(5 * 60 * 60),
            calendar: calendar
        )

        #expect(estimate.activeDuration == 190 * 60)
        #expect(estimate.longestActiveStreak == 130 * 60)
        #expect(estimate.taskSwitches == 0)
    }

    @Test
    func detectsParallelTasksAndNightWork() {
        let calendar = utcCalendar()
        let start = date("2026-07-18 20:30:00", calendar: calendar)
        let activities = [
            activity(id: "a", start: start, end: start.addingTimeInterval(90 * 60), status: .completed),
            activity(id: "b", start: start.addingTimeInterval(20 * 60), end: start.addingTimeInterval(110 * 60), status: .completed)
        ]

        let estimate = CodexFocusLoadEstimator().estimate(
            activities: activities,
            now: date("2026-07-18 23:00:00", calendar: calendar),
            calendar: calendar
        )

        #expect(estimate.maxConcurrentTasks == 2)
        #expect(estimate.lateActiveDuration == 110 * 60)
        #expect(estimate.score > 0)
    }

    @Test
    func highLoadSuggestsBreakOnlyWhileTaskIsWorking() {
        let calendar = utcCalendar()
        let start = date("2026-07-18 17:00:00", calendar: calendar)
        let working = [
            activity(id: "working-1", start: start, end: start.addingTimeInterval(5 * 60 * 60), status: .working),
            activity(id: "working-2", start: start, end: start.addingTimeInterval(5 * 60 * 60), status: .working),
            activity(id: "working-3", start: start, end: start.addingTimeInterval(5 * 60 * 60), status: .working)
        ]
        let estimator = CodexFocusLoadEstimator(workingTaskFreshness: 6 * 60 * 60)
        let estimate = estimator.estimate(
            activities: working,
            now: start.addingTimeInterval(5 * 60 * 60),
            calendar: calendar
        )

        #expect(estimate.level == .high)
        #expect(estimate.breakRecommendation == 0)

        let completed = estimator.estimate(
            activities: working.map { activity in
                self.activity(id: activity.turnID, start: start, end: start.addingTimeInterval(5 * 60 * 60), status: .completed)
            },
            now: start.addingTimeInterval(5 * 60 * 60),
            calendar: calendar
        )
        #expect(completed.breakRecommendation == nil)
    }

    @Test
    func manyTurnsInOneProjectDoNotCountAsTaskSwitching() {
        let calendar = utcCalendar()
        let start = date("2026-07-18 10:00:00", calendar: calendar)
        var activities = (0..<12).map { index in
            let turnStart = start.addingTimeInterval(TimeInterval(index * 10 * 60))
            return activity(
                id: "turn-\(index)",
                start: turnStart,
                end: turnStart.addingTimeInterval(8 * 60),
                status: .completed
            )
        }
        activities.append(activity(
            id: "working",
            start: start.addingTimeInterval(120 * 60),
            end: start.addingTimeInterval(130 * 60),
            status: .working
        ))

        let estimate = CodexFocusLoadEstimator().estimate(
            activities: activities,
            now: start.addingTimeInterval(130 * 60),
            calendar: calendar
        )

        #expect(estimate.taskSwitches == 0)
        #expect(estimate.level == .low)
        #expect(estimate.score < 35)
    }

    @Test
    func oldHistoryDoesNotInflateCurrentFocusLoad() {
        let calendar = utcCalendar()
        let now = date("2026-07-18 15:00:00", calendar: calendar)
        let old = activity(
            id: "old",
            start: now.addingTimeInterval(-10 * 60 * 60),
            end: now.addingTimeInterval(-8 * 60 * 60),
            status: .completed
        )

        let estimate = CodexFocusLoadEstimator().estimate(
            activities: [old],
            now: now,
            calendar: calendar
        )

        #expect(estimate.score == 0)
        #expect(estimate.level == .low)
    }

    @Test
    func staleUnfinishedTaskDoesNotPretendToBeCurrentlyActive() {
        let calendar = utcCalendar()
        let now = date("2026-07-18 15:00:00", calendar: calendar)
        let staleWorking = activity(
            id: "stale-working",
            start: now.addingTimeInterval(-3 * 60 * 60),
            end: now,
            status: .working
        )

        let estimate = CodexFocusLoadEstimator().estimate(
            activities: [staleWorking],
            now: now,
            calendar: calendar
        )

        #expect(estimate.score == 0)
        #expect(estimate.level == .low)
        #expect(estimate.breakRecommendation == nil)
    }

    @Test
    func emptyHistoryHasZeroLowLoad() {
        let estimate = CodexFocusLoadEstimator().estimate(activities: [], now: Date())

        #expect(estimate.score == 0)
        #expect(estimate.level == .low)
        #expect(estimate.breakRecommendation == nil)
    }

    private func activity(
        id: String,
        start: Date,
        end: Date,
        status: CodexTaskStatus
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: "session",
            turnID: id,
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high",
            status: status,
            startedAt: start,
            completedAt: status == .completed ? end : nil,
            duration: status == .completed ? end.timeIntervalSince(start) : nil,
            timeToFirstToken: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }
}
