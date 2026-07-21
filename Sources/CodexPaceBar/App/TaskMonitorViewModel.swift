import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class TaskMonitorViewModel {
    private let coordinator: TaskMonitorCoordinator
    private let estimator = CodexTaskDurationEstimator()
    private let planEstimator = CodexPlanAwareTaskDurationEstimator()
    private let goalEstimator = CodexGoalDurationEstimator()
    private let swarmEstimator = CodexSwarmDurationEstimator()
    private let rhythmEstimator = CodexWorkRhythmEstimator()
    private let checkInPolicy = CodexDailyCheckInPolicy()
    private let summaryCalculator = CodexTaskDailySummaryCalculator()
    private let navigator = TaskNavigator()
    private var healthTracker = CodexTaskMonitorHealthTracker()
    private(set) var tasks: [CodexTaskActivity] = []
    private(set) var plans: [String: CodexTaskPlanSnapshot] = [:]
    private(set) var goals: [CodexGoalActivity] = []
    private(set) var swarms: [CodexSwarmActivity] = []
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
    var planAwareEstimatesEnabled: Bool
    var onTasksReloaded: (([CodexTaskActivity]) -> Void)?
    var onActivityReloaded: (([CodexTaskActivity], [CodexGoalActivity], [CodexSwarmActivity]) -> Void)?

    init(
        coordinator: TaskMonitorCoordinator,
        focusLoadEnabled: Bool = false,
        planAwareEstimatesEnabled: Bool = true
    ) {
        self.coordinator = coordinator
        self.focusLoadEnabled = focusLoadEnabled
        self.planAwareEstimatesEnabled = planAwareEstimatesEnabled
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
                    async let loadedPlans = coordinator.taskPlans()
                    async let loadedGoals = coordinator.goals()
                    async let loadedSwarms = coordinator.swarms()
                    async let loadedEvents = coordinator.statusEvents(since: dayStart)
                    async let loadedCheckIns = coordinator.checkIns(since: checkInStart)
                    tasks = try await loadedTasks
                    plans = Dictionary(uniqueKeysWithValues: try await loadedPlans.map { ($0.taskID, $0) })
                    goals = try await loadedGoals
                    swarms = try await loadedSwarms
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
                    onActivityReloaded?(tasks, goals, swarms)
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

    func activeGoal(at now: Date) -> CodexGoalActivity? {
        goals.first { goal in
            goal.isActive
                && goal.updatedAt <= now
                && now.timeIntervalSince(goal.updatedAt) <= Self.aggregateFreshnessWindow
        }
    }

    func activeSwarm(at now: Date) -> CodexSwarmActivity? {
        swarms.first { swarm in
            swarm.isActive
                && swarm.firstSpawnedAt <= now
                && now.timeIntervalSince(swarm.firstSpawnedAt) <= Self.aggregateFreshnessWindow
        }
    }

    private static let aggregateFreshnessWindow: TimeInterval = 2 * 60 * 60

    func recentlyFinished(at now: Date) -> [CodexTaskActivity] {
        let start = Calendar.current.startOfDay(for: now)
        return tasks.filter { task in
            task.status.isFinished && (task.completedAt ?? .distantPast) >= start
        }.prefix(20).map { $0 }
    }

    func estimate(for task: CodexTaskActivity, now: Date) -> CodexTaskDurationEstimate? {
        if planAwareEstimatesEnabled,
           let plan = plans[task.id],
           let planEstimate = planEstimator.estimate(
               for: task,
               plan: plan,
               now: now,
               history: tasks,
               plans: plans
           ) {
            recordForecast(
                entityType: .task,
                entityID: task.id,
                elapsedDuration: activeElapsed(for: task, now: now),
                estimate: planEstimate,
                forecast: nil,
                planAware: planAwareEstimate(for: task, now: now),
                now: now
            )
            return planEstimate
        }
        let fallback = estimator.estimate(for: task, now: now, history: tasks)
        recordForecast(
            entityType: .task,
            entityID: task.id,
            elapsedDuration: activeElapsed(for: task, now: now),
            estimate: fallback,
            forecast: nil,
            planAware: nil,
            now: now
        )
        return fallback
    }

    func planAwareEstimate(for task: CodexTaskActivity, now: Date) -> CodexPlanAwareTaskEstimate? {
        guard planAwareEstimatesEnabled, let plan = plans[task.id] else { return nil }
        return planEstimator.initialEstimate(
            for: task,
            plan: plan,
            now: now,
            history: tasks,
            plans: plans
        )
    }

    func completionForecast(
        for task: CodexTaskActivity,
        within horizon: TimeInterval,
        now: Date
    ) -> CodexTaskCompletionForecast? {
        if planAwareEstimatesEnabled,
           let plan = plans[task.id],
           let forecast = planEstimator.completionForecast(
               for: task,
               plan: plan,
               within: horizon,
               now: now,
               history: tasks,
               plans: plans
           ) {
            recordForecast(
                entityType: .task,
                entityID: task.id,
                elapsedDuration: activeElapsed(for: task, now: now),
                estimate: planEstimator.estimate(
                    for: task,
                    plan: plan,
                    now: now,
                    history: tasks,
                    plans: plans
                ),
                forecast: forecast,
                planAware: planAwareEstimate(for: task, now: now),
                now: now
            )
            return forecast
        }
        let fallback = estimator.completionForecast(
            for: task,
            within: horizon,
            now: now,
            history: tasks
        )
        recordForecast(
            entityType: .task,
            entityID: task.id,
            elapsedDuration: activeElapsed(for: task, now: now),
            estimate: estimator.estimate(for: task, now: now, history: tasks),
            forecast: fallback,
            planAware: nil,
            now: now
        )
        return fallback
    }

    func goalEstimate(for goal: CodexGoalActivity, now: Date) -> CodexTaskDurationEstimate? {
        let estimate = goalEstimator.estimate(for: goal, now: now, history: goals)
        recordForecast(
            entityType: .goal,
            entityID: goal.id,
            elapsedDuration: goal.activeDuration,
            estimate: estimate,
            forecast: nil,
            now: now
        )
        return estimate
    }

    func goalCompletionForecast(
        for goal: CodexGoalActivity,
        within horizon: TimeInterval,
        now: Date
    ) -> CodexTaskCompletionForecast? {
        let estimate = goalEstimator.estimate(for: goal, now: now, history: goals)
        let forecast = goalEstimator.completionForecast(for: goal, within: horizon, now: now, history: goals)
        recordForecast(
            entityType: .goal,
            entityID: goal.id,
            elapsedDuration: goal.activeDuration,
            estimate: estimate,
            forecast: forecast,
            now: now
        )
        return forecast
    }

    func swarmEstimate(for swarm: CodexSwarmActivity, now: Date) -> CodexTaskDurationEstimate? {
        let estimate = swarmEstimator.estimate(for: swarm, now: now, history: swarms)
        recordForecast(
            entityType: .swarm,
            entityID: swarm.id,
            elapsedDuration: max(0, now.timeIntervalSince(swarm.firstSpawnedAt)),
            estimate: estimate,
            forecast: nil,
            now: now
        )
        return estimate
    }

    private func recordForecast(
        entityType: CodexForecastEntityType,
        entityID: String,
        elapsedDuration: TimeInterval,
        estimate: CodexTaskDurationEstimate?,
        forecast: CodexTaskCompletionForecast?,
        planAware: CodexPlanAwareTaskEstimate? = nil,
        now: Date
    ) {
        guard let estimate else { return }
        let bucket = Int(max(0, elapsedDuration) / (5 * 60))
        let observation = CodexForecastObservation(
            id: "\(entityType.rawValue):\(entityID):\(bucket)",
            entityType: entityType,
            entityID: entityID,
            observedAt: now,
            elapsedDuration: elapsedDuration,
            medianRemaining: estimate.medianRemaining,
            safeRemaining: estimate.safeRemaining,
            probabilityWithinHorizon: forecast?.probability,
            horizon: forecast?.horizon,
            sampleCount: estimate.sampleCount,
            scope: estimate.scope,
            typicalTotal: planAware?.typicalTotal,
            upperTotal: planAware?.planUpperTotal,
            safeAwayRemaining: planAware?.safeAwayRemaining,
            model: planAware?.model ?? .baseline
        )
        Task { @MainActor [weak self] in
            try? await self?.coordinator.recordForecast(observation)
        }
    }

    private func activeElapsed(for task: CodexTaskActivity, now: Date) -> TimeInterval {
        let raw = task.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let openWaiting = task.waitingStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, raw - task.waitingDuration - openWaiting)
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
                goals = []
                swarms = []
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
