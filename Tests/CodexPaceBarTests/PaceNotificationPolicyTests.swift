import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct PaceNotificationPolicyTests {
    @Test
    func notificationThresholdUsesDoubleThePaceDelta() {
        #expect(PaceNotificationPolicy.notificationDeltaThreshold(deltaThresholdPercentagePoints: 2) == 4)
        #expect(PaceNotificationPolicy.notificationDeltaThreshold(deltaThresholdPercentagePoints: 5) == 10)
    }

    @Test
    func notifiesWhenUsageIsAtLeastDoubleThePaceDelta() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = snapshot(delta: 4, now: now)

        #expect(PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: 2,
            lastNotificationSentAt: nil,
            now: now
        ))
    }

    @Test
    func doesNotNotifyBelowDoubleThePaceDelta() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = snapshot(delta: 3.9, now: now)

        #expect(!PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: 2,
            lastNotificationSentAt: nil,
            now: now
        ))
    }

    @Test
    func cooldownPreventsRepeatedDailyNotifications() {
        let now = Date(timeIntervalSince1970: 100_000)
        let snapshot = snapshot(delta: 8, now: now)

        #expect(!PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: 2,
            lastNotificationSentAt: now.addingTimeInterval(-(23 * 60 * 60)),
            now: now
        ))

        #expect(PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: 2,
            lastNotificationSentAt: now.addingTimeInterval(-(24 * 60 * 60)),
            now: now
        ))
    }

    @Test
    func staleSnapshotsDoNotNotify() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = snapshot(delta: 8, now: now, isStale: true)

        #expect(!PaceNotificationPolicy.shouldNotify(
            snapshot: snapshot,
            deltaThresholdPercentagePoints: 2,
            lastNotificationSentAt: nil,
            now: now
        ))
    }

    private func snapshot(delta: Double, now: Date, isStale: Bool = false) -> PaceSnapshot {
        PaceSnapshot(
            actualUsedPercent: 50 + delta,
            remainingPercent: 50 - delta,
            idealUsedPercent: 50,
            deltaPercentagePoints: delta,
            usedFraction: 0.5,
            elapsedFraction: 0.5,
            resetAt: now.addingTimeInterval(60),
            state: delta > 0 ? .abovePace : .onPace,
            fetchedAt: now,
            isStale: isStale
        )
    }
}
