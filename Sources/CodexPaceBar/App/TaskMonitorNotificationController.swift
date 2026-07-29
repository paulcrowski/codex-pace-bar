import CodexPaceBarCore
import CodexPaceBarAppSupport
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class TaskMonitorNotificationController {
    private let notificationCenter: UNUserNotificationCenter
    private let mobileService: MobileTaskNotificationService
    private var pendingLocalWaitingAlerts: [String: PendingLocalWaitingAlert] = [:]
    private var mobileBaselinePrepared = false
    private var previousMobileEnabled = false
    private var previousMobileTopic = ""
    private var previousMobileDetailsEnabled = false
    private var previousSilentGoalsAndSwarmsEnabled = false

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        mobileService: MobileTaskNotificationService = MobileTaskNotificationService()
    ) {
        self.notificationCenter = notificationCenter
        self.mobileService = mobileService
    }

    func notifyIfNeeded(
        for tasks: [CodexTaskActivity],
        goals: [CodexGoalActivity] = [],
        swarms: [CodexSwarmActivity] = [],
        localEnabled: Bool,
        mobileEnabled: Bool,
        mobileTopic: String,
        mobileDetailsEnabled: Bool,
        silentGoalsAndSwarmsEnabled: Bool,
        now: Date = Date()
    ) {
        if localEnabled {
            deliverLocalNotificationsIfNeeded(for: tasks, now: now)
        }

        let configurationChanged = mobileEnabled != previousMobileEnabled
            || mobileTopic != previousMobileTopic
            || mobileDetailsEnabled != previousMobileDetailsEnabled
            || silentGoalsAndSwarmsEnabled != previousSilentGoalsAndSwarmsEnabled
        previousMobileEnabled = mobileEnabled
        previousMobileTopic = mobileTopic
        previousMobileDetailsEnabled = mobileDetailsEnabled
        previousSilentGoalsAndSwarmsEnabled = silentGoalsAndSwarmsEnabled
        if !mobileBaselinePrepared || configurationChanged {
            mobileService.discardPendingCompletionBatch()
            mobileService.prime(with: tasks, goals: goals, swarms: swarms)
            mobileBaselinePrepared = true
            return
        }

        Task { [mobileService] in
            await mobileService.notifyIfNeeded(
                for: tasks,
                enabled: mobileEnabled,
                topic: mobileTopic,
                includeDetails: mobileDetailsEnabled,
                silentGoalsAndSwarmsEnabled: silentGoalsAndSwarmsEnabled,
                goals: goals,
                swarms: swarms,
                now: now
            )
        }
    }

    func resetMobileBaseline() {
        mobileBaselinePrepared = false
        mobileService.discardPendingCompletionBatch()
        mobileService.discardPendingWaitingAlerts()
        cancelAllPendingLocalWaitingAlerts()
    }

    func sendMobileTest(topic: String) async -> Bool {
        await mobileService.sendTest(topic: topic)
    }

    private func deliverLocalNotificationsIfNeeded(for tasks: [CodexTaskActivity], now: Date) {
        let waitingTasks = tasks.filter { $0.status.isWaitingForUser }
        let waitingIDs = Set(waitingTasks.map(\.id))

        let finishedWaitingIDs = pendingLocalWaitingAlerts.keys.filter { !waitingIDs.contains($0) }
        for taskID in finishedWaitingIDs {
            guard let pending = pendingLocalWaitingAlerts[taskID] else { continue }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [pending.requestIdentifier])
            pendingLocalWaitingAlerts.removeValue(forKey: taskID)
        }

        for task in waitingTasks {
            let waitingStartedAt = task.waitingStartedAt ?? task.lastEventAt ?? now
            let episodeKey = "\(task.id):waiting:\(waitingStartedAt.timeIntervalSince1970)"
            if let pending = pendingLocalWaitingAlerts[task.id] {
                if pending.episodeKey == episodeKey {
                    continue
                }
                notificationCenter.removePendingNotificationRequests(
                    withIdentifiers: [pending.requestIdentifier]
                )
                pendingLocalWaitingAlerts.removeValue(forKey: task.id)
            }

            let age = now.timeIntervalSince(waitingStartedAt)
            guard age >= -30, age <= MobileTaskNotificationService.maximumEventAge else { continue }

            let delay = max(0, MobileTaskNotificationService.waitingNotificationDelay - age)
            let requestIdentifier = "codex-task-needs-user-\(task.id)"
            pendingLocalWaitingAlerts[task.id] = PendingLocalWaitingAlert(
                episodeKey: episodeKey,
                requestIdentifier: requestIdentifier
            )
            Task { [notificationCenter] in
                let settings = await notificationCenter.notificationSettings()
                let allowed: Bool
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: allowed = true
                case .notDetermined:
                    allowed = (try? await notificationCenter.requestAuthorization(options: [.alert])) ?? false
                default: allowed = false
                }
                guard allowed else {
                    _ = await MainActor.run { self.removePendingLocalWaitingAlert(
                        taskID: task.id,
                        episodeKey: episodeKey,
                        cancelRequest: false
                    ) }
                    return
                }
                guard await MainActor.run(body: {
                    self.pendingLocalWaitingAlerts[task.id]?.episodeKey == episodeKey
                }) else { return }

                let content = UNMutableNotificationContent()
                content.title = "Codex needs you"
                content.body = task.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "A task is waiting for a response."
                let trigger = delay > 0
                    ? UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, delay), repeats: false)
                    : nil
                do {
                    try await notificationCenter.add(UNNotificationRequest(
                        identifier: requestIdentifier,
                        content: content,
                        trigger: trigger
                    ))
                } catch {
                    _ = await MainActor.run { self.removePendingLocalWaitingAlert(
                        taskID: task.id,
                        episodeKey: episodeKey,
                        cancelRequest: false
                    ) }
                }
            }
        }
    }

    private func removePendingLocalWaitingAlert(
        taskID: String,
        episodeKey: String,
        cancelRequest: Bool
    ) {
        guard let pending = pendingLocalWaitingAlerts[taskID],
              pending.episodeKey == episodeKey
        else { return }
        pendingLocalWaitingAlerts.removeValue(forKey: taskID)
        if cancelRequest {
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: [pending.requestIdentifier]
            )
        }
    }

    private func cancelAllPendingLocalWaitingAlerts() {
        let identifiers = pendingLocalWaitingAlerts.values.map(\.requestIdentifier)
        if !identifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        pendingLocalWaitingAlerts.removeAll()
    }

    private struct PendingLocalWaitingAlert {
        let episodeKey: String
        let requestIdentifier: String
    }
}
