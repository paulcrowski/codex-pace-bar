import CodexPaceBarCore
import Foundation
import Testing

struct DailyCheckInPolicyTests {
    @Test
    func offersYesterdayBeforeTodayWhenYesterdayWasNotRated() throws {
        let calendar = utcCalendar()
        let now = date("2026-07-19 10:00:00", calendar: calendar)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let activities = [completedActivity(at: date("2026-07-18 16:00:00", calendar: calendar))]

        let prompt = CodexDailyCheckInPolicy().prompt(
            activities: activities,
            checkIns: [],
            now: now,
            calendar: calendar
        )

        #expect(prompt?.period == .yesterday)
        #expect(calendar.isDate(prompt?.day ?? .distantPast, inSameDayAs: yesterday))
    }

    @Test
    func movesToTodayAfterYesterdayIsRated() throws {
        let calendar = utcCalendar()
        let now = date("2026-07-19 10:00:00", calendar: calendar)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let activities = [
            completedActivity(at: date("2026-07-18 16:00:00", calendar: calendar)),
            completedActivity(at: date("2026-07-19 09:30:00", calendar: calendar))
        ]

        let prompt = CodexDailyCheckInPolicy().prompt(
            activities: activities,
            checkIns: [CodexDailyWorkCheckIn(day: yesterday, rating: .calm)],
            now: now,
            calendar: calendar
        )

        #expect(prompt?.period == .today)
        #expect(calendar.isDate(prompt?.day ?? .distantPast, inSameDayAs: now))
    }

    @Test
    func doesNotBackfillAnythingOlderThanYesterday() {
        let calendar = utcCalendar()
        let now = date("2026-07-19 10:00:00", calendar: calendar)
        let activities = [completedActivity(at: date("2026-07-17 16:00:00", calendar: calendar))]

        let prompt = CodexDailyCheckInPolicy().prompt(
            activities: activities,
            checkIns: [],
            now: now,
            calendar: calendar
        )

        #expect(prompt == nil)
    }

    @Test
    func usesLastYesterdayActivityForCatchUpRhythmScore() throws {
        let calendar = utcCalendar()
        let now = date("2026-07-19 10:00:00", calendar: calendar)
        let prompt = try #require(CodexDailyCheckInPolicy().prompt(
            activities: [completedActivity(at: date("2026-07-18 16:00:00", calendar: calendar))],
            checkIns: [],
            now: now,
            calendar: calendar
        ))
        let justAfterLastActivity = date("2026-07-18 16:00:01", calendar: calendar)

        #expect(abs(prompt.scoreDate.timeIntervalSince(justAfterLastActivity)) < 1)
    }

    private func completedActivity(at completedAt: Date) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: UUID().uuidString,
            turnID: UUID().uuidString,
            workingDirectory: "/work/project",
            model: nil,
            effort: nil,
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-600),
            completedAt: completedAt,
            duration: 600,
            timeToFirstToken: nil,
            lastEventAt: completedAt
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
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }
}
