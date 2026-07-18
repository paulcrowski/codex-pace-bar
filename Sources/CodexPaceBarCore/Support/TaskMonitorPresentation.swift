import Foundation

public enum CodexTaskSummaryState: Equatable, Sendable {
    case noActiveTasks
    case working(count: Int)
    case needsYou(count: Int)
}

public struct CodexTaskSummaryPresentation: Equatable, Sendable {
    public let state: CodexTaskSummaryState
    public let title: String
    public let projectName: String?
    public let elapsedText: String?
    public let estimateText: String?
    public let additionalTasksText: String?
    public let freshnessText: String

    public init(
        state: CodexTaskSummaryState,
        title: String,
        projectName: String?,
        elapsedText: String?,
        estimateText: String?,
        additionalTasksText: String?,
        freshnessText: String
    ) {
        self.state = state
        self.title = title
        self.projectName = projectName
        self.elapsedText = elapsedText
        self.estimateText = estimateText
        self.additionalTasksText = additionalTasksText
        self.freshnessText = freshnessText
    }
}

public struct CodexTaskSummaryPresenter: Sendable {
    private let estimator: CodexTaskDurationEstimator

    public init(estimator: CodexTaskDurationEstimator = CodexTaskDurationEstimator()) {
        self.estimator = estimator
    }

    public func present(
        needsYou: [CodexTaskActivity],
        working: [CodexTaskActivity],
        history: [CodexTaskActivity],
        now: Date,
        lastUpdatedAt: Date?
    ) -> CodexTaskSummaryPresentation {
        let activeCount = needsYou.count + working.count
        guard activeCount > 0 else {
            return CodexTaskSummaryPresentation(
                state: .noActiveTasks,
                title: "No active tasks",
                projectName: nil,
                elapsedText: nil,
                estimateText: nil,
                additionalTasksText: nil,
                freshnessText: freshnessText(lastUpdatedAt, now: now)
            )
        }

        let waiting = !needsYou.isEmpty
        let visibleTasks = waiting ? needsYou : working
        let task = visibleTasks[0]
        let state: CodexTaskSummaryState = waiting
            ? .needsYou(count: activeCount)
            : .working(count: activeCount)
        let title: String = {
            switch state {
            case .needsYou(let count):
                return count == 1 ? "Needs you · 1 active" : "Needs you · \(count) active"
            case .working(let count):
                return count == 1 ? "Working · 1 active" : "Working · \(count) active"
            case .noActiveTasks:
                return "No active tasks"
            }
        }()

        let additionalCount = max(0, activeCount - 1)
        return CodexTaskSummaryPresentation(
            state: state,
            title: title,
            projectName: projectName(for: task),
            elapsedText: elapsedText(for: task, now: now),
            estimateText: waiting ? nil : estimateText(for: task, now: now, history: history),
            additionalTasksText: additionalCount > 0 ? "+\(additionalCount) other active task\(additionalCount == 1 ? "" : "s")" : nil,
            freshnessText: freshnessText(lastUpdatedAt, now: now)
        )
    }

    private func projectName(for task: CodexTaskActivity) -> String {
        task.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? task.turnID
    }

    private func elapsedText(for task: CodexTaskActivity, now: Date) -> String {
        let seconds = task.duration ?? task.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        if task.status.isWaitingForUser, let waitingStartedAt = task.waitingStartedAt {
            return "Waiting \(durationText(max(0, now.timeIntervalSince(waitingStartedAt))))"
        }
        return durationText(seconds)
    }

    private func estimateText(
        for task: CodexTaskActivity,
        now: Date,
        history: [CodexTaskActivity]
    ) -> String? {
        guard let estimate = estimator.estimate(for: task, now: now, history: history) else {
            return nil
        }
        guard estimate.confidence == .learned,
              let median = estimate.medianRemaining,
              let safe = estimate.safeRemaining
        else {
            return "Learning · \(estimate.sampleCount)/\(estimator.minimumSamples) samples"
        }
        return "ETA \(durationRangeText(median, safe))"
    }

    private func durationRangeText(_ lower: TimeInterval, _ upper: TimeInterval) -> String {
        "\(durationText(lower))–\(durationText(upper))"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private func freshnessText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Waiting for local activity" }
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        if seconds < 5 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds) sec ago" }
        return "Updated \(seconds / 60) min ago"
    }
}
