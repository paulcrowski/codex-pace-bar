import Foundation

public struct CodexTaskDailySummary: Equatable, Sendable {
    public let activeWallTime: TimeInterval
    public let agentHours: TimeInterval
    public let waitingForUser: TimeInterval
    public let completedTasks: Int

    public init(
        activeWallTime: TimeInterval,
        agentHours: TimeInterval,
        waitingForUser: TimeInterval,
        completedTasks: Int
    ) {
        self.activeWallTime = activeWallTime
        self.agentHours = agentHours
        self.waitingForUser = waitingForUser
        self.completedTasks = completedTasks
    }
}

public struct CodexTaskDailySummaryCalculator: Sendable {
    private let activeTaskFreshnessWindow: TimeInterval = 2 * 60 * 60

    public init() {}

    public func calculate(
        activities: [CodexTaskActivity],
        events: [CodexTaskStatusEvent],
        day: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> CodexTaskDailySummary {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = min(calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now, now)
        let eventsByTask = Dictionary(grouping: events, by: \.taskID)
        var activeIntervals: [Interval] = []
        var agentHours: TimeInterval = 0
        var waitingForUser: TimeInterval = 0

        for activity in activities {
            let taskEnd: Date
            if activity.status.isFinished {
                guard let completedAt = activity.completedAt else { continue }
                taskEnd = completedAt
            } else {
                guard let lastActivityAt = activity.lastEventAt ?? activity.startedAt,
                      now.timeIntervalSince(lastActivityAt) <= activeTaskFreshnessWindow
                else {
                    continue
                }
                taskEnd = now
            }

            var taskEvents = eventsByTask[activity.id, default: []].sorted { $0.occurredAt < $1.occurredAt }
            taskEvents = taskEvents.filter { $0.occurredAt <= taskEnd }
            if taskEvents.isEmpty, let startedAt = activity.startedAt {
                taskEvents = [CodexTaskStatusEvent(
                    sessionID: activity.sessionID,
                    turnID: activity.turnID,
                    status: .working,
                    occurredAt: startedAt
                )]
            }
            for (index, event) in taskEvents.enumerated() {
                let end = index + 1 < taskEvents.count ? taskEvents[index + 1].occurredAt : taskEnd
                guard let clipped = clip(start: event.occurredAt, end: end, dayStart: dayStart, dayEnd: dayEnd) else {
                    continue
                }
                if event.status == .working {
                    activeIntervals.append(clipped)
                    agentHours += clipped.duration
                } else if event.status.isWaitingForUser {
                    waitingForUser += clipped.duration
                }
            }
        }

        return CodexTaskDailySummary(
            activeWallTime: merge(activeIntervals).reduce(0) { $0 + $1.duration },
            agentHours: agentHours,
            waitingForUser: waitingForUser,
            completedTasks: activities.filter {
                guard $0.status == .completed, let completedAt = $0.completedAt else { return false }
                return completedAt >= dayStart && completedAt < dayEnd
            }.count
        )
    }

    private func clip(start: Date, end: Date, dayStart: Date, dayEnd: Date) -> Interval? {
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(max(end, start), dayEnd)
        return clippedEnd > clippedStart ? Interval(start: clippedStart, end: clippedEnd) : nil
    }

    private func merge(_ intervals: [Interval]) -> [Interval] {
        var result: [Interval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            guard let last = result.last else {
                result.append(interval)
                continue
            }
            if interval.start <= last.end {
                result[result.count - 1].end = max(last.end, interval.end)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private struct Interval {
        var start: Date
        var end: Date
        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }
}
