import CodexPaceBarCore
import Foundation
import Testing

struct TaskDailySummaryTests {
    @Test
    func separatesWallTimeAgentHoursAndWaitingForUser() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let first = activity("a", start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(11 * 3600))
        let second = activity("b", start: day.addingTimeInterval(10 * 3600), end: day.addingTimeInterval(12 * 3600))
        let events = [
            event("a", .working, day, 9), event("a", .needsApproval, day, 10),
            event("a", .working, day, 10.5), event("a", .completed, day, 11),
            event("b", .working, day, 10), event("b", .completed, day, 12)
        ]

        let result = CodexTaskDailySummaryCalculator().calculate(
            activities: [first, second],
            events: events,
            day: day,
            now: day.addingTimeInterval(13 * 3600),
            calendar: calendar
        )

        #expect(result.activeWallTime == 3 * 3600)
        #expect(result.agentHours == 3.5 * 3600)
        #expect(result.waitingForUser == 0.5 * 3600)
        #expect(result.completedTasks == 2)
    }

    @Test
    func ignoresStaleActiveTaskInsteadOfCountingItUntilNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let stale = CodexTaskActivity(
            sessionID: "s",
            turnID: "stale",
            workingDirectory: nil,
            model: nil,
            effort: nil,
            status: .working,
            startedAt: day.addingTimeInterval(9 * 3600),
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil,
            lastEventAt: day.addingTimeInterval(12 * 3600)
        )

        let result = CodexTaskDailySummaryCalculator().calculate(
            activities: [stale],
            events: [],
            day: day,
            now: day.addingTimeInterval(19 * 3600),
            calendar: calendar
        )

        #expect(result.activeWallTime == 0)
        #expect(result.agentHours == 0)
        #expect(result.waitingForUser == 0)
    }

    @Test
    func countsFreshActiveTaskUntilNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let task = CodexTaskActivity(
            sessionID: "s",
            turnID: "fresh",
            workingDirectory: nil,
            model: nil,
            effort: nil,
            status: .working,
            startedAt: day.addingTimeInterval(10 * 3600),
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil,
            lastEventAt: day.addingTimeInterval(12 * 3600 + 59 * 60)
        )

        let result = CodexTaskDailySummaryCalculator().calculate(
            activities: [task],
            events: [],
            day: day,
            now: day.addingTimeInterval(13 * 3600),
            calendar: calendar
        )

        #expect(result.activeWallTime == 3 * 3600)
        #expect(result.agentHours == 3 * 3600)
    }

    @Test
    func clipsAWorkingAndWaitingTaskThatCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let task = activity(
            "overnight",
            start: day.addingTimeInterval(-3600),
            end: day.addingTimeInterval(2 * 3600)
        )
        let events = [
            event("overnight", .working, day, -1),
            event("overnight", .needsApproval, day, -0.5),
            event("overnight", .working, day, 0.5),
            event("overnight", .completed, day, 2)
        ]

        let result = CodexTaskDailySummaryCalculator().calculate(
            activities: [task],
            events: events,
            day: day,
            now: day.addingTimeInterval(3 * 3600),
            calendar: calendar
        )

        #expect(result.activeWallTime == 1.5 * 3600)
        #expect(result.agentHours == 1.5 * 3600)
        #expect(result.waitingForUser == 0.5 * 3600)
        #expect(result.completedTasks == 1)
    }

    private func activity(_ id: String, start: Date, end: Date) -> CodexTaskActivity {
        CodexTaskActivity(sessionID: "s", turnID: id, workingDirectory: nil, model: nil, effort: nil, status: .completed, startedAt: start, completedAt: end, duration: end.timeIntervalSince(start), timeToFirstToken: nil)
    }

    private func event(_ id: String, _ status: CodexTaskStatus, _ day: Date, _ hour: Double) -> CodexTaskStatusEvent {
        CodexTaskStatusEvent(sessionID: "s", turnID: id, status: status, occurredAt: day.addingTimeInterval(hour * 3600))
    }
}
