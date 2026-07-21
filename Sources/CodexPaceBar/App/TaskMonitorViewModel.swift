import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class TaskMonitorViewModel {
    private let coordinator: TaskMonitorCoordinator
    private let estimator = CodexTaskDurationEstimator()
    private let rhythmEstimator = CodexWorkRhythmEstimator()
    private let checkInPolicy = CodexDailyCheckInPolicy()
    private let summaryCalculator = CodexTaskDailySummaryCalculator()
    private let navigator = TaskNavigator()
    private var healthTracker = CodexTaskMonitorHealthTracker()
    private(set) var tasks: [CodexTaskActivity] = []
    private(set) var events: [CodexTaskStatusEvent] = []
    private(set) var checkIns: [CodexDailyWorkCheckIn] = []
    private(set) var lastReloadDate: Date?
    private(set) var health: CodexTaskMonitorHealth = .loading
    private(set) var todaySummary = CodexTaskDailySummary(
        activeWallTime: 0,
        agentHours: 0,
        waitingForUser: 0,
        completedTasks: 0
    )
    private var isReloading = false
    private var reloadRequested = false
    var focusLoadEnabled: Bool
    var onTasksReloaded: (([CodexTaskActivity]) -> Void)?

    init(coordinator: TaskMonitorCoordinator, focusLoadEnabled: Bool = false) {
        self.coordinator = coordinator
        self.focusLoadEnabled = focusLoadEnabled
        coordinator.onChange = { [weak self] in self?.reload() }
        coordinator.onError = { [weak self] error in
            guard let self else { return }
            healthTracker.markStale(message: Self.userFacingErrorMessage(for: error))
            health = healthTracker.state
        }
        reload()
    }

    func reload(now: Date = Date()) {
        if isReloading {
            reloadRequested = true
            return
        }
        isReloading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var reloadDate = now
            repeat {
                reloadRequested = false
                do {
                    let currentReloadDate = reloadDate
                    let dayStart = Calendar.current.startOfDay(for: currentReloadDate)
                    let checkInStart = currentReloadDate.addingTimeInterval(-90 * 24 * 60 * 60)
                    async let loadedTasks = coordinator.tasks()
                    async let loadedEvents = coordinator.statusEvents(since: dayStart)
                    async let loadedCheckIns = coordinator.checkIns(since: checkInStart)
                    tasks = try await loadedTasks
                    events = try await loadedEvents
                    checkIns = try await loadedCheckIns
                    todaySummary = summaryCalculator.calculate(
                        activities: tasks,
                        events: events,
                        day: currentReloadDate,
                        now: currentReloadDate
                    )
                    lastReloadDate = currentReloadDate
                    healthTracker.markReady()
                    health = healthTracker.state
                    onTasksReloaded?(tasks)
                } catch {
                    healthTracker.markStale(message: Self.userFacingErrorMessage(for: error))
                    health = healthTracker.state
                }
                reloadDate = Date()
            } while reloadRequested
            isReloading = false
        }
    }

    func needsYou(at now: Date) -> [CodexTaskActivity] {
        freshTasks(at: now).filter { $0.status.isWaitingForUser }
    }

    func working(at now: Date) -> [CodexTaskActivity] {
        freshTasks(at: now).filter(\.isRunning)
    }

    func hasActiveTasks(at now: Date) -> Bool {
        !needsYou(at: now).isEmpty || !working(at: now).isEmpty
    }

    func recentlyFinished(at now: Date) -> [CodexTaskActivity] {
        let start = Calendar.current.startOfDay(for: now)
        return tasks.filter { task in
            task.status.isFinished && (task.completedAt ?? .distantPast) >= start
        }.prefix(20).map { $0 }
    }

    func estimate(for task: CodexTaskActivity, now: Date) -> CodexTaskDurationEstimate? {
        estimator.estimate(for: task, now: now, history: tasks)
    }

    func completionForecast(
        for task: CodexTaskActivity,
        within horizon: TimeInterval,
        now: Date
    ) -> CodexTaskCompletionForecast? {
        estimator.completionForecast(
            for: task,
            within: horizon,
            now: now,
            history: tasks
        )
    }

    func typicalDuration(at now: Date) -> CodexTaskDurationDistribution? {
        estimator.distribution(history: tasks, now: now)
    }

    func workRhythm(at now: Date) -> CodexWorkRhythmEstimate? {
        guard focusLoadEnabled else { return nil }
        return rhythmEstimator.estimate(activities: tasks, checkIns: checkIns, now: now)
    }

    func checkInPrompt(at now: Date) -> CodexDailyCheckInPrompt? {
        guard focusLoadEnabled else { return nil }
        return checkInPolicy.prompt(activities: tasks, checkIns: checkIns, now: now)
    }

    func saveCheckIn(_ rating: CodexDailyWorkRating, for prompt: CodexDailyCheckInPrompt) {
        let score = rhythmEstimator.estimate(
            activities: tasks,
            checkIns: checkIns,
            now: prompt.scoreDate
        ).source.score
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await coordinator.saveCheckIn(rating: rating, rhythmScore: score, day: prompt.day)
                let saved = CodexDailyWorkCheckIn(day: prompt.day, rating: rating, rhythmScore: score)
                if let index = checkIns.firstIndex(where: {
                    Calendar.current.isDate($0.day, inSameDayAs: prompt.day)
                }) {
                    checkIns[index] = saved
                } else {
                    checkIns.append(saved)
                }
            } catch {
                healthTracker.markStale(message: Self.userFacingErrorMessage(for: error))
                health = healthTracker.state
            }
        }
    }

    func currentCheckIn(on day: Date) -> CodexDailyWorkRating? {
        return checkIns.first { Calendar.current.isDate($0.day, inSameDayAs: day) }?.rating
    }

    func clearHistory() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await coordinator.clearHistory()
                tasks = []
                events = []
                checkIns = []
                todaySummary = CodexTaskDailySummary(
                    activeWallTime: 0,
                    agentHours: 0,
                    waitingForUser: 0,
                    completedTasks: 0
                )
                lastReloadDate = Date()
            } catch {
                healthTracker.markStale(message: Self.userFacingErrorMessage(for: error))
                health = healthTracker.state
            }
        }
    }

    func canNavigate(to task: CodexTaskActivity) -> Bool {
        navigator.bundleIdentifier(for: task) != nil
    }

    func navigate(to task: CodexTaskActivity) {
        _ = navigator.navigate(to: task)
    }

    private func freshTasks(at now: Date) -> [CodexTaskActivity] {
        tasks.filter { task in
            guard task.status.isActive else { return false }
            return now.timeIntervalSince(task.lastEventAt ?? task.startedAt ?? .distantPast) <= 2 * 60 * 60
        }
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "Could not read local Codex activity. Showing the last successful snapshot."
        }
        return "Could not read local Codex activity (\(detail)). Showing the last successful snapshot."
    }
}
