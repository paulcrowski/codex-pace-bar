import Foundation

public enum PaceNotificationPolicy {
    public static let cooldownSeconds: TimeInterval = 24 * 60 * 60
    public static let deltaMultiplier = 2.0

    public static func notificationDeltaThreshold(deltaThresholdPercentagePoints: Int) -> Double {
        max(0, Double(deltaThresholdPercentagePoints) * deltaMultiplier)
    }

    public static func shouldNotify(
        snapshot: PaceSnapshot,
        deltaThresholdPercentagePoints: Int,
        lastNotificationSentAt: Date?,
        now: Date
    ) -> Bool {
        guard !snapshot.isStale else {
            return false
        }

        let notificationThreshold = notificationDeltaThreshold(
            deltaThresholdPercentagePoints: deltaThresholdPercentagePoints
        )
        guard snapshot.deltaPercentagePoints >= notificationThreshold else {
            return false
        }

        guard let lastNotificationSentAt else {
            return true
        }

        return now.timeIntervalSince(lastNotificationSentAt) >= cooldownSeconds
    }
}
