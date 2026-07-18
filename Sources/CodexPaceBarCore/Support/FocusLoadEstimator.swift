import Foundation

public enum CodexFocusLoadLevel: String, Codable, Sendable {
    case low
    case moderate
    case high
}

public struct CodexFocusLoadEstimate: Equatable, Sendable {
    public let score: Int
    public let level: CodexFocusLoadLevel
    public let activeDuration: TimeInterval
    public let longestActiveStreak: TimeInterval
    public let taskSwitches: Int
    public let maxConcurrentTasks: Int
    public let lateActiveDuration: TimeInterval
    public let breakRecommendation: TimeInterval?

    public init(
        score: Int,
        level: CodexFocusLoadLevel,
        activeDuration: TimeInterval,
        longestActiveStreak: TimeInterval,
        taskSwitches: Int,
        maxConcurrentTasks: Int,
        lateActiveDuration: TimeInterval,
        breakRecommendation: TimeInterval?
    ) {
        self.score = score
        self.level = level
        self.activeDuration = activeDuration
        self.longestActiveStreak = longestActiveStreak
        self.taskSwitches = taskSwitches
        self.maxConcurrentTasks = maxConcurrentTasks
        self.lateActiveDuration = lateActiveDuration
        self.breakRecommendation = breakRecommendation
    }
}

public struct CodexFocusLoadEstimator: Sendable {
    public static let defaultBreakInterval: TimeInterval = 20 * 60
    public static let defaultLookbackInterval: TimeInterval = 4 * 60 * 60
    public static let defaultWorkingTaskFreshness: TimeInterval = 2 * 60 * 60
    public static let highLoadThreshold = 75

    public let breakInterval: TimeInterval
    public let lookbackInterval: TimeInterval
    public let workingTaskFreshness: TimeInterval
    public let highLoadThreshold: Int

    public init(
        breakInterval: TimeInterval = Self.defaultBreakInterval,
        lookbackInterval: TimeInterval = Self.defaultLookbackInterval,
        workingTaskFreshness: TimeInterval = Self.defaultWorkingTaskFreshness,
        highLoadThreshold: Int = Self.highLoadThreshold
    ) {
        self.breakInterval = max(0, breakInterval)
        self.lookbackInterval = max(0, lookbackInterval)
        self.workingTaskFreshness = max(0, workingTaskFreshness)
        self.highLoadThreshold = min(max(highLoadThreshold, 1), 100)
    }

    public func estimate(
        activities: [CodexTaskActivity],
        now: Date,
        calendar: Calendar = .current
    ) -> CodexFocusLoadEstimate {
        let windowStart = now.addingTimeInterval(-lookbackInterval)
        let intervals = activities.compactMap { activity -> ActivityInterval? in
            guard let startedAt = activity.startedAt else {
                return nil
            }

            let inferredWorkingEnd = min(
                now,
                startedAt.addingTimeInterval(workingTaskFreshness)
            )
            let completedAt = activity.completedAt ?? inferredWorkingEnd
            let end = min(max(completedAt, startedAt), now)
            guard end >= windowStart, startedAt <= now else {
                return nil
            }
            return ActivityInterval(
                id: activity.id,
                projectKey: activity.workingDirectory ?? activity.sessionID,
                start: max(startedAt, windowStart),
                end: end,
                isWorking: activity.status == .working && end == now
            )
        }
        .sorted { $0.start < $1.start }

        guard !intervals.isEmpty else {
            return CodexFocusLoadEstimate(
                score: 0,
                level: .low,
                activeDuration: 0,
                longestActiveStreak: 0,
                taskSwitches: 0,
                maxConcurrentTasks: 0,
                lateActiveDuration: 0,
                breakRecommendation: nil
            )
        }

        let merged = merge(intervals, allowingGap: breakInterval)
        let union = merge(intervals, allowingGap: 0)
        let activeDuration = merged.reduce(0) { $0 + $1.duration }
        let longestActiveStreak = merged.map(\.duration).max() ?? 0
        let taskSwitches = projectSwitchCount(intervals)
        let maxConcurrentTasks = maximumConcurrency(intervals)
        let lateActiveDuration = union.reduce(0) {
            $0 + lateOverlap(from: $1.start, to: $1.end, calendar: calendar)
        }
        let hasWorkingTask = intervals.contains { $0.isWorking && $0.end == now }
        let currentStreak = merged.first(where: { $0.end == now })?.duration ?? 0

        let currentConcurrency = intervals.filter { $0.isWorking && $0.end == now }.count
        let streakScore = min(40, currentStreak / (4 * 60 * 60) * 40)
        let switchScore = min(20, Double(taskSwitches) / 8 * 20)
        let concurrencyScore = min(20, Double(max(0, currentConcurrency - 1)) / 2 * 20)
        let lateScore = min(20, lateActiveDuration / (2 * 60 * 60) * 20)
        let score = min(100, Int((streakScore + switchScore + concurrencyScore + lateScore).rounded()))
        let level: CodexFocusLoadLevel
        if score >= highLoadThreshold {
            level = .high
        } else if score >= 35 {
            level = .moderate
        } else {
            level = .low
        }

        let breakRecommendation: TimeInterval?
        if level == .high, hasWorkingTask {
            breakRecommendation = max(0, 2 * 60 * 60 - currentStreak)
        } else {
            breakRecommendation = nil
        }

        return CodexFocusLoadEstimate(
            score: score,
            level: level,
            activeDuration: activeDuration,
            longestActiveStreak: longestActiveStreak,
            taskSwitches: taskSwitches,
            maxConcurrentTasks: maxConcurrentTasks,
            lateActiveDuration: lateActiveDuration,
            breakRecommendation: breakRecommendation
        )
    }

    private func merge(
        _ intervals: [ActivityInterval],
        allowingGap gap: TimeInterval
    ) -> [MergedInterval] {
        var merged: [MergedInterval] = []
        for interval in intervals {
            guard let last = merged.last else {
                merged.append(MergedInterval(start: interval.start, end: interval.end))
                continue
            }

            if interval.start.timeIntervalSince(last.end) <= gap {
                merged[merged.index(before: merged.endIndex)].end = max(last.end, interval.end)
            } else {
                merged.append(MergedInterval(start: interval.start, end: interval.end))
            }
        }
        return merged
    }

    private func maximumConcurrency(_ intervals: [ActivityInterval]) -> Int {
        let events = intervals.flatMap { [
            ($0.start, 1),
            ($0.end, -1)
        ] }
        .sorted { left, right in
            if left.0 == right.0 {
                return left.1 < right.1
            }
            return left.0 < right.0
        }

        var current = 0
        var maximum = 0
        for (_, delta) in events {
            current += delta
            maximum = max(maximum, current)
        }
        return maximum
    }

    private func projectSwitchCount(_ intervals: [ActivityInterval]) -> Int {
        guard var previous = intervals.first?.projectKey else {
            return 0
        }
        var switches = 0
        for interval in intervals.dropFirst() where interval.projectKey != previous {
            switches += 1
            previous = interval.projectKey
        }
        return switches
    }

    private func lateOverlap(from start: Date, to end: Date, calendar: Calendar) -> TimeInterval {
        var day = calendar.startOfDay(for: start)
        var total: TimeInterval = 0

        while day <= end {
            guard let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day),
                  let nextMorning = calendar.date(
                      bySettingHour: 6,
                      minute: 0,
                      second: 0,
                      of: calendar.date(byAdding: .day, value: 1, to: day)!
                  )
            else {
                break
            }
            total += overlap(from: start, to: end, with: evening, and: nextMorning)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }
        return total
    }

    private func overlap(from start: Date, to end: Date, with otherStart: Date, and otherEnd: Date) -> TimeInterval {
        max(0, min(end, otherEnd).timeIntervalSince(max(start, otherStart)))
    }

    private struct ActivityInterval {
        let id: String
        let projectKey: String
        let start: Date
        let end: Date
        let isWorking: Bool
    }

    private struct MergedInterval {
        let start: Date
        var end: Date

        var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
    }
}

public enum CodexWorkRhythmLevel: String, Equatable, Sendable {
    case calm
    case intense
    case veryIntense
}

public struct CodexWorkRhythmEstimate: Equatable, Sendable {
    public let level: CodexWorkRhythmLevel
    public let detail: String
    public let isPersonallyCalibrated: Bool
    public let source: CodexFocusLoadEstimate

    public init(
        level: CodexWorkRhythmLevel,
        detail: String,
        isPersonallyCalibrated: Bool,
        source: CodexFocusLoadEstimate
    ) {
        self.level = level
        self.detail = detail
        self.isPersonallyCalibrated = isPersonallyCalibrated
        self.source = source
    }
}

public struct CodexWorkRhythmEstimator: Sendable {
    public let minimumCalibrationDays: Int

    public init(minimumCalibrationDays: Int = 20) {
        self.minimumCalibrationDays = max(1, minimumCalibrationDays)
    }

    public func estimate(
        activities: [CodexTaskActivity],
        checkIns: [CodexDailyWorkCheckIn],
        now: Date,
        calendar: Calendar = .current
    ) -> CodexWorkRhythmEstimate {
        let scored = checkIns.compactMap { checkIn -> (CodexDailyWorkRating, Int)? in
            checkIn.rhythmScore.map { (checkIn.rating, $0) }
        }
        let calibrated = scored.count >= minimumCalibrationDays
        let personalHighThreshold: Int
        if calibrated {
            let demanding = scored.filter { $0.0 == .tooMuch }.map(\.1).sorted()
            personalHighThreshold = demanding.isEmpty ? 75 : max(55, median(demanding))
        } else {
            personalHighThreshold = 75
        }
        let source = CodexFocusLoadEstimator(highLoadThreshold: personalHighThreshold)
            .estimate(activities: activities, now: now, calendar: calendar)
        let level: CodexWorkRhythmLevel = switch source.level {
        case .low: .calm
        case .moderate: .intense
        case .high: .veryIntense
        }
        let detail: String
        switch level {
        case .calm:
            detail = "Calm rhythm. This describes activity, not computer load."
        case .intense:
            detail = "Intense rhythm, without an alert."
        case .veryIntense:
            detail = source.maxConcurrentTasks > 1
                ? "Several tasks are running in parallel. Consider a short break."
                : "Long active session. Consider a short break."
        }
        return CodexWorkRhythmEstimate(
            level: level,
            detail: detail,
            isPersonallyCalibrated: calibrated,
            source: source
        )
    }

    private func median(_ values: [Int]) -> Int {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
