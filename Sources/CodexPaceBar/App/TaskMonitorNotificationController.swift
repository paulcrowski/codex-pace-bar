import CodexPaceBarCore
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class TaskMonitorNotificationController {
    private let notificationCenter: UNUserNotificationCenter
    private var deliveredKeys = Set<String>()

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func notifyIfNeeded(for tasks: [CodexTaskActivity], enabled: Bool, now: Date = Date()) {
        guard enabled else { return }
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
