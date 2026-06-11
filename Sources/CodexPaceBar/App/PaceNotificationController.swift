import CodexPaceBarCore
import Foundation
import UserNotifications

@MainActor
final class PaceNotificationController {
    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func notifyIfNeeded(snapshot: PaceSnapshot, settings: SettingsStore, now: Date = Date()) {
        guard settings.notificationsEnabled else {
            return
        }

        let lastNotificationSentAt = defaults.object(forKey: Keys.lastNotificationSentAt) as? Date
        guard PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: settings.deltaThresholdPercentagePoints,
            lastNotificationSentAt: lastNotificationSentAt,
            now: now
        ) else {
            return
        }

        defaults.set(now, forKey: Keys.lastNotificationSentAt)
        Task {
            await deliver(snapshot: snapshot)
        }
    }

    private func deliver(snapshot: PaceSnapshot) async {
        guard await notificationPermissionIsAvailable() else {
            return
        }

        let delta = Int(snapshot.deltaPercentagePoints.rounded())
        let content = UNMutableNotificationContent()
        content.title = "Codex usage is above pace"
        content.body = "Your current usage is \(delta) percentage points ahead of the normal pace."

        let request = UNNotificationRequest(
            identifier: "codex-pace-above-pace-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    private func notificationPermissionIsAvailable() async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private enum Keys {
        static let lastNotificationSentAt = "lastPaceNotificationSentAt"
    }
}
