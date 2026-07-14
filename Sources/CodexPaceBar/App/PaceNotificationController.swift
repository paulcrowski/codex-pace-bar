import CodexPaceBarCore
import Foundation
import UserNotifications

@MainActor
final class PaceNotificationController {
    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private var isDelivering = false

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func notifyIfNeeded(
        snapshot: PaceSnapshot,
        forecast: UsageForecast?,
        enabled: Bool,
        deltaThresholdPercentagePoints: Int,
        now: Date = Date()
    ) {
        guard enabled, !isDelivering else {
            return
        }

        let lastNotificationSentAt = defaults.object(forKey: Keys.lastNotificationSentAt) as? Date
        let notification = notification(
            snapshot: snapshot,
            forecast: forecast,
            deltaThresholdPercentagePoints: deltaThresholdPercentagePoints,
            lastNotificationSentAt: lastNotificationSentAt,
            now: now
        )
        guard let notification else {
            return
        }

        isDelivering = true
        Task { [weak self] in
            guard let self else {
                return
            }

            if await deliver(notification: notification) {
                defaults.set(now, forKey: Keys.lastNotificationSentAt)
            }
            isDelivering = false
        }
    }

    private func notification(
        snapshot: PaceSnapshot,
        forecast: UsageForecast?,
        deltaThresholdPercentagePoints: Int,
        lastNotificationSentAt: Date?,
        now: Date
    ) -> NotificationMessage? {
        if let forecast,
           PaceNotificationPolicy.shouldNotifyForecast(
               forecast: forecast,
               snapshot: snapshot,
               lastNotificationSentAt: lastNotificationSentAt,
               now: now
           ) {
            let hours = max(1, Int(forecast.hoursUntilExhaustion(at: now).rounded(.up)))
            return NotificationMessage(
                title: "Codex limit may run out early",
                body: "Based on your usage, the weekly limit may run out in about \(hours) hours."
            )
        }

        guard PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: deltaThresholdPercentagePoints,
            lastNotificationSentAt: lastNotificationSentAt,
            now: now
        ) else {
            return nil
        }

        let delta = Int(snapshot.deltaPercentagePoints.rounded())
        return NotificationMessage(
            title: "Codex usage is above pace",
            body: "Your current usage is \(delta) percentage points ahead of the normal pace."
        )
    }

    private func deliver(notification: NotificationMessage) async -> Bool {
        guard await notificationPermissionIsAvailable() else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body

        let request = UNNotificationRequest(
            identifier: "codex-pace-notification-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            return false
        }
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

    private struct NotificationMessage {
        let title: String
        let body: String
    }
}
