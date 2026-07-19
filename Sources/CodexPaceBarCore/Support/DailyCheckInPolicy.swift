import Foundation

public enum CodexDailyCheckInPeriod: Equatable, Sendable {
    case today
    case yesterday
}

public struct CodexDailyCheckInPrompt: Equatable, Sendable {
    public let period: CodexDailyCheckInPeriod
    public let day: Date
    public let scoreDate: Date

    public init(period: CodexDailyCheckInPeriod, day: Date, scoreDate: Date) {
        self.period = period
        self.day = day
        self.scoreDate = scoreDate
    }
}

public struct CodexDailyCheckInPolicy: Sendable {
    public init() {}

    public func prompt(
        activities: [CodexTaskActivity],
        checkIns: [CodexDailyWorkCheckIn],
        now: Date,
        calendar: Calendar = .current
    ) -> CodexDailyCheckInPrompt? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return nil
        }

        if !hasCheckIn(on: yesterday, checkIns: checkIns, calendar: calendar),
           let lastActivity = lastActivityDate(on: yesterday, activities: activities, calendar: calendar),
           let endOfYesterday = calendar.date(byAdding: .second, value: -1, to: today) {
            return CodexDailyCheckInPrompt(
                period: .yesterday,
                day: yesterday,
                scoreDate: min(lastActivity.addingTimeInterval(1), endOfYesterday)
            )
        }

        let todayIsRated = hasCheckIn(on: today, checkIns: checkIns, calendar: calendar)
        let todayHasCompletedWork = activities.contains { activity in
            guard let completedAt = activity.completedAt else { return false }
            return completedAt >= today && completedAt < tomorrow
        }
        guard todayIsRated || todayHasCompletedWork || calendar.component(.hour, from: now) >= 18 else {
            return nil
        }

        return CodexDailyCheckInPrompt(period: .today, day: today, scoreDate: now)
    }

    private func hasCheckIn(
        on day: Date,
        checkIns: [CodexDailyWorkCheckIn],
        calendar: Calendar
    ) -> Bool {
        checkIns.contains { calendar.isDate($0.day, inSameDayAs: day) }
    }

    private func lastActivityDate(
        on day: Date,
        activities: [CodexTaskActivity],
        calendar: Calendar
    ) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return activities.flatMap { activity in
            [activity.startedAt, activity.completedAt, activity.lastEventAt]
                .compactMap { $0 }
                .filter { $0 >= day && $0 < nextDay }
        }
        .max()
    }
}
