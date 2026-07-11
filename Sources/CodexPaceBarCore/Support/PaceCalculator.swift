import Foundation

public struct PaceThresholds: Equatable, Sendable {
    public static let `default` = PaceThresholds(deltaPercentagePoints: 2)

    public let deltaPercentagePoints: Double

    public init(deltaPercentagePoints: Double) {
        self.deltaPercentagePoints = max(0, deltaPercentagePoints)
    }

    var releasePercentagePoints: Double {
        deltaPercentagePoints * 0.6
    }
}

public enum PaceCalculator {
    public static func snapshot(
        for window: CodexLimitWindow,
        now: Date,
        fetchedAt: Date,
        previousState: PaceState?,
        isStale: Bool = false,
        thresholds: PaceThresholds = .default
    ) -> PaceSnapshot {
        let actualUsedPercent = clamp(window.usedPercent, 0, 100)
        let remainingPercent = clamp(100 - actualUsedPercent, 0, 100)
        let periodDurationSeconds = max(window.windowDurationMins * 60, 1)
        let periodStart = window.resetsAt.addingTimeInterval(-periodDurationSeconds)
        let elapsedFraction = clamp(now.timeIntervalSince(periodStart) / periodDurationSeconds, 0, 1)
        let idealUsedPercent = elapsedFraction * 100
        let usedFraction = clamp(actualUsedPercent / 100, 0, 1)
        let delta = actualUsedPercent - idealUsedPercent
        let state = classify(delta: delta, previousState: previousState, thresholds: thresholds)

        return PaceSnapshot(
            actualUsedPercent: actualUsedPercent,
            remainingPercent: remainingPercent,
            idealUsedPercent: idealUsedPercent,
            deltaPercentagePoints: delta,
            usedFraction: usedFraction,
            elapsedFraction: elapsedFraction,
            resetAt: window.resetsAt,
            state: state,
            fetchedAt: fetchedAt,
            isStale: isStale
        )
    }

    public static func classify(
        delta: Double,
        previousState: PaceState?,
        thresholds: PaceThresholds = .default
    ) -> PaceState {
        guard let previousState, previousState.isValidPaceState else {
            return initialState(delta: delta, thresholds: thresholds)
        }

        switch previousState {
        case .onPace:
            if delta <= -thresholds.deltaPercentagePoints {
                return .belowPace
            }
            if delta >= thresholds.deltaPercentagePoints {
                return .abovePace
            }
            return .onPace
        case .belowPace:
            return delta > -thresholds.releasePercentagePoints ? .onPace : .belowPace
        case .abovePace:
            return delta < thresholds.releasePercentagePoints ? .onPace : .abovePace
        case .loading, .error:
            return initialState(delta: delta, thresholds: thresholds)
        }
    }

    private static func initialState(delta: Double, thresholds: PaceThresholds) -> PaceState {
        if delta <= -thresholds.deltaPercentagePoints {
            return .belowPace
        }
        if delta >= thresholds.deltaPercentagePoints {
            return .abovePace
        }
        return .onPace
    }
}
