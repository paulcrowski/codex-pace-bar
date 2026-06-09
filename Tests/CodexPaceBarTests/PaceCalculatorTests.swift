import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct PaceCalculatorTests {
    @Test
    func paceClassificationUsesInitialThresholds() {
        let resetAt = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)
        let halfway = resetAt.addingTimeInterval(-3.5 * 24 * 60 * 60)

        #expect(snapshot(used: 48, now: halfway, resetAt: resetAt).state == .belowPace)
        #expect(snapshot(used: 51, now: halfway, resetAt: resetAt).state == .onPace)
        #expect(snapshot(used: 52, now: halfway, resetAt: resetAt).state == .abovePace)
    }

    @Test
    func customThresholdsCanUseFivePercentagePoints() {
        let thresholds = PaceThresholds(deltaPercentagePoints: 5)

        #expect(PaceCalculator.classify(delta: -5, previousState: nil, thresholds: thresholds) == .belowPace)
        #expect(PaceCalculator.classify(delta: 3, previousState: nil, thresholds: thresholds) == .onPace)
        #expect(PaceCalculator.classify(delta: 5, previousState: nil, thresholds: thresholds) == .abovePace)
    }

    @Test
    func elapsedFractionIsClamped() {
        let resetAt = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)
        let beforeStart = Date(timeIntervalSince1970: -100)
        let afterReset = resetAt.addingTimeInterval(100)

        #expect(snapshot(used: 0, now: beforeStart, resetAt: resetAt).elapsedFraction == 0)
        #expect(snapshot(used: 100, now: afterReset, resetAt: resetAt).elapsedFraction == 1)
    }

    @Test
    func hysteresisTransitions() {
        #expect(PaceCalculator.classify(delta: -2, previousState: .onPace) == .belowPace)
        #expect(PaceCalculator.classify(delta: -1.2, previousState: .belowPace) == .belowPace)
        #expect(PaceCalculator.classify(delta: -1.1, previousState: .belowPace) == .onPace)

        #expect(PaceCalculator.classify(delta: 2, previousState: .onPace) == .abovePace)
        #expect(PaceCalculator.classify(delta: 1.2, previousState: .abovePace) == .abovePace)
        #expect(PaceCalculator.classify(delta: 1.1, previousState: .abovePace) == .onPace)
    }

    @Test
    func staleFlagIsPreserved() {
        let resetAt = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)
        let now = resetAt.addingTimeInterval(-60)

        #expect(snapshot(used: 90, now: now, resetAt: resetAt, isStale: true).isStale)
    }

    @Test
    func hoursUntilOnPaceUsesWeeklyPaceRate() {
        let resetAt = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)
        let halfway = resetAt.addingTimeInterval(-3.5 * 24 * 60 * 60)
        let current = snapshot(used: 60, now: halfway, resetAt: resetAt)
        let window = CodexLimitWindow(
            limitId: "codex",
            source: "test",
            usedPercent: 60,
            windowDurationMins: 10080,
            resetsAt: resetAt
        )

        let hours = PaceCalculator.hoursUntilOnPace(snapshot: current, window: window)
        #expect(abs((hours ?? 0) - 16.8) < 0.001)
    }

    @Test
    func hoursUntilOnPaceIsOnlyShownWhenOverspent() {
        let resetAt = Date(timeIntervalSince1970: 7 * 24 * 60 * 60)
        let halfway = resetAt.addingTimeInterval(-3.5 * 24 * 60 * 60)
        let current = snapshot(used: 50, now: halfway, resetAt: resetAt)
        let window = CodexLimitWindow(
            limitId: "codex",
            source: "test",
            usedPercent: 50,
            windowDurationMins: 10080,
            resetsAt: resetAt
        )

        #expect(PaceCalculator.hoursUntilOnPace(snapshot: current, window: window) == nil)
    }

    private func snapshot(used: Double, now: Date, resetAt: Date, isStale: Bool = false) -> PaceSnapshot {
        let window = CodexLimitWindow(
            limitId: "codex",
            source: "test",
            usedPercent: used,
            windowDurationMins: 10080,
            resetsAt: resetAt
        )
        return PaceCalculator.snapshot(
            for: window,
            now: now,
            fetchedAt: now,
            previousState: nil,
            isStale: isStale
        )
    }
}
