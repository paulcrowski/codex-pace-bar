import CodexPaceBarCore
import Foundation

@MainActor
public final class MobileTaskNotificationService {
    public typealias RequestSender = (URLRequest) async throws -> (Data, URLResponse)

    public static let maximumEventAge: TimeInterval = 5 * 60
    public static let defaultQuietInterval: TimeInterval = 90
    public static let requestTimeout: TimeInterval = 10
    public static let maximumSendAttempts = 3
    public static let retryBaseDelay: TimeInterval = 0.05
    public static let aggregateFreshnessWindow: TimeInterval = 2 * 60 * 60
    public static let ntfyBaseURL = URL(string: "https://ntfy.sh")!

    private static let deliveredKeysDefaultsKey = "mobileTaskNotificationDeliveredKeys"
    private static let maximumDeliveredKeys = 512

    private let defaults: UserDefaults
    private let sender: RequestSender
    private let quietInterval: TimeInterval
    private var deliveredKeys: Set<String>
    private var deliveredOrder: [String]
    private var inFlightKeys = Set<String>()
    private var pendingCompletionTasks: [String: CodexTaskActivity] = [:]
    private var latestQuietTasks: [CodexTaskActivity] = []
    private var latestQuietGoals: [CodexGoalActivity] = []
    private var latestQuietSwarms: [CodexSwarmActivity] = []
    private var quietPublishURL: URL?
    private var quietIncludeDetails = false
    private var quietFlushTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        quietInterval: TimeInterval = MobileTaskNotificationService.defaultQuietInterval,
        sender: @escaping RequestSender = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.defaults = defaults
        self.sender = sender
        self.quietInterval = max(0, quietInterval)
        let storedKeys = defaults.stringArray(forKey: Self.deliveredKeysDefaultsKey) ?? []
        self.deliveredKeys = Set(storedKeys)
        self.deliveredOrder = storedKeys
    }

    public func prime(
        with tasks: [CodexTaskActivity],
        goals: [CodexGoalActivity] = [],
        swarms: [CodexSwarmActivity] = []
    ) {
        let keys = tasks
            .filter { message(for: $0) != nil }
            .sorted { eventDate(for: $0) < eventDate(for: $1) }
            .map(eventKey(for:))
        let aggregateKeys = goals.filter(\.isTerminal).map(goalEventKey)
            + swarms.filter { $0.completedAt != nil }.map(swarmEventKey)
        recordDelivered(keys + aggregateKeys)
    }

    public func notifyIfNeeded(
        for tasks: [CodexTaskActivity],
        enabled: Bool,
        topic: String,
        includeDetails: Bool = false,
        silentGoalsAndSwarmsEnabled: Bool = false,
        goals: [CodexGoalActivity] = [],
        swarms: [CodexSwarmActivity] = [],
        now: Date = Date()
    ) async {
        guard enabled, let publishURL = Self.publishURL(topic: topic) else {
            discardPendingCompletionBatch()
            return
        }

        if silentGoalsAndSwarmsEnabled {
            await deliverImmediateWaitingAlerts(
                from: tasks,
                to: publishURL,
                includeDetails: includeDetails,
                now: now
            )
            await deliverNativeTerminalAlerts(
                goals: goals,
                swarms: swarms,
                now: now,
                to: publishURL,
                includeDetails: includeDetails
            )
            queueFreshCompletions(from: tasks, goals: goals, swarms: swarms, now: now)
            latestQuietTasks = tasks
            latestQuietGoals = goals
            latestQuietSwarms = swarms
            quietPublishURL = publishURL
            quietIncludeDetails = includeDetails

            if hasBlockingActivity(tasks: tasks, goals: goals, swarms: swarms, now: now) {
                quietFlushTask?.cancel()
                quietFlushTask = nil
            } else {
                scheduleQuietFlushIfNeeded()
            }
            return
        }

        discardPendingCompletionBatch()
        await deliverIndividually(
            tasks,
            to: publishURL,
            includeDetails: includeDetails,
            now: now
        )
    }

    public func discardPendingCompletionBatch() {
        quietFlushTask?.cancel()
        quietFlushTask = nil
        pendingCompletionTasks.removeAll()
        latestQuietTasks.removeAll()
        latestQuietGoals.removeAll()
        latestQuietSwarms.removeAll()
        quietPublishURL = nil
    }

    private func deliverIndividually(
        _ tasks: [CodexTaskActivity],
        to publishURL: URL,
        includeDetails: Bool,
        now: Date
    ) async {
        for task in tasks.sorted(by: { eventDate(for: $0) < eventDate(for: $1) }) {
            guard let message = message(for: task, includeDetails: includeDetails) else { continue }
            await deliver(message, for: task, to: publishURL, now: now)
        }
    }

    private func deliverImmediateWaitingAlerts(
        from tasks: [CodexTaskActivity],
        to publishURL: URL,
        includeDetails: Bool,
        now: Date
    ) async {
        for task in tasks where task.status.isWaitingForUser {
            guard let message = message(for: task, includeDetails: includeDetails) else { continue }
            await deliver(message, for: task, to: publishURL, now: now)
        }
    }

    private func deliver(_ message: Message, for task: CodexTaskActivity, to url: URL, now: Date) async {
        await deliver(message, key: eventKey(for: task), occurredAt: eventDate(for: task), to: url, now: now)
    }

    private func deliver(
        _ message: Message,
        key: String,
        occurredAt date: Date,
        to url: URL,
        now: Date
    ) async {
        let age = now.timeIntervalSince(date)
        guard age >= -30, age <= Self.maximumEventAge else { return }

        guard !deliveredKeys.contains(key), !inFlightKeys.contains(key) else { return }
        inFlightKeys.insert(key)
        let delivered = await send(message, to: url)
        inFlightKeys.remove(key)
        if delivered {
            recordDelivered([key])
        }
    }

    private func queueFreshCompletions(
        from tasks: [CodexTaskActivity],
        goals: [CodexGoalActivity],
        swarms: [CodexSwarmActivity],
        now: Date
    ) {
        for task in tasks where task.status == .completed {
            let age = now.timeIntervalSince(eventDate(for: task))
            guard age >= -30, age <= Self.maximumEventAge else { continue }
            let key = eventKey(for: task)
            guard !deliveredKeys.contains(key), !inFlightKeys.contains(key) else { continue }
            guard !belongsToAggregate(task, goals: goals, swarms: swarms) else { continue }
            pendingCompletionTasks[key] = task
        }
    }

    private func hasActiveTasks(_ tasks: [CodexTaskActivity], now: Date) -> Bool {
        tasks.contains { task in
            guard task.isRunning || task.status.isWaitingForUser else { return false }
            let age = now.timeIntervalSince(eventDate(for: task))
            return age >= -30 && age <= 2 * 60 * 60
        }
    }

    private func hasBlockingActivity(
        tasks: [CodexTaskActivity],
        goals: [CodexGoalActivity],
        swarms: [CodexSwarmActivity],
        now: Date
    ) -> Bool {
        hasActiveTasks(tasks, now: now)
            || goals.contains(where: {
                $0.isActive
                    && now >= $0.updatedAt
                    && now.timeIntervalSince($0.updatedAt) <= Self.aggregateFreshnessWindow
            })
            || swarms.contains(where: {
                $0.isActive
                    && now >= $0.firstSpawnedAt
                    && now.timeIntervalSince($0.firstSpawnedAt) <= Self.aggregateFreshnessWindow
            })
    }

    private func belongsToAggregate(
        _ task: CodexTaskActivity,
        goals: [CodexGoalActivity],
        swarms: [CodexSwarmActivity]
    ) -> Bool {
        goals.contains { $0.threadID == task.sessionID }
            || swarms.contains { $0.sessionID == task.sessionID }
    }

    private func deliverNativeTerminalAlerts(
        goals: [CodexGoalActivity],
        swarms: [CodexSwarmActivity],
        now: Date,
        to url: URL,
        includeDetails: Bool
    ) async {
        for goal in goals where goal.isTerminal {
            await deliver(
                goalMessage(for: goal, includeDetails: includeDetails),
                key: goalEventKey(goal),
                occurredAt: goal.updatedAt,
                to: url,
                now: now
            )
        }
        for swarm in swarms where swarm.completedAt != nil
            && !goals.contains(where: { $0.threadID == swarm.sessionID && $0.isTerminal }) {
            await deliver(
                swarmMessage(for: swarm, includeDetails: includeDetails),
                key: swarmEventKey(swarm),
                occurredAt: swarm.completedAt ?? swarm.firstSpawnedAt,
                to: url,
                now: now
            )
        }
    }

    private func scheduleQuietFlushIfNeeded() {
        guard quietFlushTask == nil,
              !pendingCompletionTasks.isEmpty,
              quietPublishURL != nil else {
            return
        }

        let delayNanoseconds = UInt64(quietInterval * 1_000_000_000)
        quietFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.flushQuietBatch()
        }
    }

    private func flushQuietBatch() async {
        quietFlushTask = nil
        guard let publishURL = quietPublishURL,
              !hasBlockingActivity(
                tasks: latestQuietTasks,
                goals: latestQuietGoals,
                swarms: latestQuietSwarms,
                now: Date()
              ) else {
            return
        }

        let entries = pendingCompletionTasks
            .filter { !deliveredKeys.contains($0.key) && !inFlightKeys.contains($0.key) }
            .sorted { eventDate(for: $0.value) < eventDate(for: $1.value) }
        guard !entries.isEmpty else { return }

        let keys = entries.map(\.key)
        let tasks = entries.map(\.value)
        inFlightKeys.formUnion(keys)
        let delivered = await send(
            completionBatchMessage(for: tasks, includeDetails: quietIncludeDetails),
            to: publishURL
        )
        inFlightKeys.subtract(keys)

        if delivered {
            recordDelivered(keys)
            keys.forEach { pendingCompletionTasks.removeValue(forKey: $0) }
            return
        }

        scheduleQuietFlushIfNeeded()
    }

    public func sendTest(topic: String) async -> Bool {
        guard let publishURL = Self.publishURL(topic: topic) else {
            return false
        }
        return await send(
            Message(
                title: "Codex Pace Bar test",
                body: "Phone notifications are connected.",
                priority: "high",
                tags: "white_check_mark"
            ),
            to: publishURL
        )
    }

    public static func publishURL(topic: String) -> URL? {
        guard isValid(topic: topic) else { return nil }
        return ntfyBaseURL.appendingPathComponent(topic)
    }

    public static func androidSubscriptionURL(topic: String) -> URL? {
        guard isValid(topic: topic) else { return nil }
        var components = URLComponents()
        components.scheme = "ntfy"
        components.host = "ntfy.sh"
        components.path = "/\(topic)"
        components.queryItems = [
            URLQueryItem(name: "display", value: "Codex Pace Bar")
        ]
        return components.url
    }

    public static func isValid(topic: String) -> Bool {
        guard !topic.isEmpty, topic.count <= 64 else { return false }
        return topic.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || value == 45
                || value == 95
        }
    }

    private func send(_ message: Message, to url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(message.body.utf8)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(message.title, forHTTPHeaderField: "Title")
        request.setValue(message.priority, forHTTPHeaderField: "Priority")
        request.setValue(message.tags, forHTTPHeaderField: "Tags")

        for attempt in 0..<Self.maximumSendAttempts {
            do {
                try Task.checkCancellation()
                let (_, response) = try await sender(request)
                guard let response = response as? HTTPURLResponse else { return false }
                if (200..<300).contains(response.statusCode) {
                    return true
                }
                guard Self.shouldRetry(statusCode: response.statusCode), attempt + 1 < Self.maximumSendAttempts else {
                    return false
                }
            } catch is CancellationError {
                return false
            } catch {
                guard attempt + 1 < Self.maximumSendAttempts else { return false }
            }

            let delay = Self.retryBaseDelay * Double(1 << attempt)
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            } catch {
                return false
            }
        }
        return false
    }

    private static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
    }

    private func message(for task: CodexTaskActivity, includeDetails: Bool = false) -> Message? {
        switch task.status {
        case .completed:
            return Message(
                title: "Codex task finished",
                body: includeDetails
                    ? completedDetails(for: task)
                    : "A Codex task is ready on your Mac.",
                priority: "high",
                tags: "white_check_mark"
            )
        case .needsApproval, .needsInput:
            return Message(
                title: "Codex needs you",
                body: includeDetails
                    ? waitingDetails(for: task)
                    : "A Codex task is waiting for approval or input on your Mac.",
                priority: "high",
                tags: "warning"
            )
        case .queued, .working, .failed, .cancelled, .stale:
            return nil
        }
    }

    private func completedDetails(for task: CodexTaskActivity) -> String {
        let project = projectName(for: task)
        let duration = task.duration.flatMap(durationText)
        switch (project, duration) {
        case let (.some(project), .some(duration)):
            return "Task in \(project) completed in \(duration)."
        case let (.some(project), .none):
            return "Task in \(project) completed."
        case let (.none, .some(duration)):
            return "Task completed in \(duration)."
        case (.none, .none):
            return "A Codex task is ready on your Mac."
        }
    }

    private func goalMessage(for goal: CodexGoalActivity, includeDetails: Bool) -> Message {
        let project = projectName(for: goal.workingDirectory)
        let title = goal.status == .complete ? "Codex goal finished" : "Codex goal needs you"
        let body: String
        if includeDetails, let project {
            body = goal.status == .complete
                ? "Goal in \(project) completed."
                : "A goal in \(project) is blocked and needs attention."
        } else {
            body = goal.status == .complete
                ? "A Codex goal finished on your Mac."
                : "A Codex goal is blocked on your Mac."
        }
        return Message(title: title, body: body, priority: "high", tags: goal.status == .complete ? "white_check_mark" : "warning")
    }

    private func swarmMessage(for swarm: CodexSwarmActivity, includeDetails: Bool) -> Message {
        let project = projectName(for: swarm.workingDirectory)
        let body: String
        if includeDetails, let project {
            body = "Swarm in \(project) completed with \(swarm.agentCount) agent\(swarm.agentCount == 1 ? "" : "s")."
        } else {
            body = "A Codex swarm finished on your Mac."
        }
        return Message(title: "Codex swarm finished", body: body, priority: "high", tags: "white_check_mark")
    }

    private func projectName(for path: String?) -> String? {
        guard let path else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : String(name.prefix(60))
    }

    private func waitingDetails(for task: CodexTaskActivity) -> String {
        guard let project = projectName(for: task) else {
            return "A Codex task is waiting for approval or input on your Mac."
        }
        return "A task in \(project) is waiting for approval or input."
    }

    private func completionBatchMessage(
        for tasks: [CodexTaskActivity],
        includeDetails: Bool
    ) -> Message {
        let body: String
        if tasks.count == 1, let task = tasks.first {
            body = includeDetails
                ? completedDetails(for: task)
                : "A Codex task is ready on your Mac."
        } else if includeDetails {
            let projects = Set(tasks.compactMap(projectName(for:)))
            if projects.count == 1, let project = projects.first {
                body = "\(tasks.count) tasks in \(project) completed."
            } else if projects.count > 1 {
                body = "\(tasks.count) Codex tasks completed across \(projects.count) projects."
            } else {
                body = "\(tasks.count) Codex tasks completed."
            }
        } else {
            body = "\(tasks.count) Codex tasks completed."
        }

        return Message(
            title: "Codex work ready",
            body: body,
            priority: "high",
            tags: "white_check_mark"
        )
    }

    private func projectName(for task: CodexTaskActivity) -> String? {
        guard let path = task.workingDirectory else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let safe = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(safe))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(60))
    }

    private func durationText(_ interval: TimeInterval) -> String? {
        guard interval >= 0, interval.isFinite else { return nil }
        let totalMinutes = max(1, Int((interval / 60).rounded()))
        guard totalMinutes >= 60 else { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    private func eventDate(for task: CodexTaskActivity) -> Date {
        task.lastEventAt ?? task.completedAt ?? task.waitingStartedAt ?? task.startedAt ?? .distantPast
    }

    private func eventKey(for task: CodexTaskActivity) -> String {
        let timestamp = eventDate(for: task).timeIntervalSince1970
        return "\(task.id):\(task.status.rawValue):\(timestamp)"
    }

    private func goalEventKey(_ goal: CodexGoalActivity) -> String {
        "goal:\(goal.id):\(goal.status.rawValue):\(goal.updatedAt.timeIntervalSince1970)"
    }

    private func swarmEventKey(_ swarm: CodexSwarmActivity) -> String {
        "swarm:\(swarm.id):complete:\(swarm.completedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func recordDelivered(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        for key in keys where deliveredKeys.insert(key).inserted {
            deliveredOrder.append(key)
        }
        if deliveredOrder.count > Self.maximumDeliveredKeys {
            let overflow = deliveredOrder.count - Self.maximumDeliveredKeys
            let removed = deliveredOrder.prefix(overflow)
            deliveredOrder.removeFirst(overflow)
            deliveredKeys.subtract(removed)
        }
        defaults.set(deliveredOrder, forKey: Self.deliveredKeysDefaultsKey)
    }

    private struct Message {
        let title: String
        let body: String
        let priority: String
        let tags: String
    }
}
