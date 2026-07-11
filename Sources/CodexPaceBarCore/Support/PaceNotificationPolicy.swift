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

        return cooldownHasElapsed(lastNotificationSentAt: lastNotificationSentAt, now: now)
    }

    public static func shouldNotifyForecast(
        forecast: UsageForecast,
        snapshot: PaceSnapshot,
        lastNotificationSentAt: Date?,
        now: Date
    ) -> Bool {
        guard !snapshot.isStale,
              forecast.willRunOutBeforeReset,
              forecast.exhaustionAt > now
        else {
            return false
        }

        return cooldownHasElapsed(lastNotificationSentAt: lastNotificationSentAt, now: now)
    }

    private static func cooldownHasElapsed(lastNotificationSentAt: Date?, now: Date) -> Bool {
        guard let lastNotificationSentAt else {
            return true
        }
        return now.timeIntervalSince(lastNotificationSentAt) >= cooldownSeconds
    }
}
