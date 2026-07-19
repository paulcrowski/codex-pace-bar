import CodexPaceBarCore
import CodexPaceBarAppSupport
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class TaskMonitorNotificationController {
    private let notificationCenter: UNUserNotificationCenter
    private let mobileService: MobileTaskNotificationService
    private var deliveredKeys = Set<String>()
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
            mobileService.prime(with: tasks)
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
                now: now
            )
        }
    }

    func resetMobileBaseline() {
        mobileBaselinePrepared = false
        mobileService.discardPendingCompletionBatch()
    }

    func sendMobileTest(topic: String) async -> Bool {
        await mobileService.sendTest(topic: topic)
    }

    private func deliverLocalNotificationsIfNeeded(for tasks: [CodexTaskActivity], now: Date) {
        for task in tasks where task.status == .needsApproval || task.status == .needsInput {
            let key = "\(task.id):\(task.status.rawValue):\(task.lastEventAt?.timeIntervalSince1970 ?? 0)"
            guard !deliveredKeys.contains(key),
                  now.timeIntervalSince(task.lastEventAt ?? .distantPast) < 5 * 60
            else { continue }
            deliveredKeys.insert(key)
            Task { [notificationCenter] in
                let settings = await notificationCenter.notificationSettings()
                let allowed: Bool
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: allowed = true
                case .notDetermined:
                    allowed = (try? await notificationCenter.requestAuthorization(options: [.alert])) ?? false
                default: allowed = false
                }
                guard allowed else { return }
                let content = UNMutableNotificationContent()
                content.title = "Codex needs you"
                content.body = task.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "A task is waiting for a response."
                try? await notificationCenter.add(UNNotificationRequest(
                    identifier: "codex-task-needs-user-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                ))
            }
        }
    }
}
