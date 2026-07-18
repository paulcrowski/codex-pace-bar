import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    public enum Failure: Equatable {
        case codexSetupRequired(String)
        case refreshFailed(String)

        public var message: String {
            switch self {
            case let .codexSetupRequired(message), let .refreshFailed(message):
                return message
            }
        }

        public var requiresCodexSetup: Bool {
            if case .codexSetupRequired = self {
                return true
            }
            return false
        }
    }

    public var snapshot: PaceSnapshot?
    public var selectedWindow: CodexLimitWindow?
    public var forecast: UsageForecast?
    public var failure: Failure?
    public var isRefreshing = false
    public var lastCheckedAt: Date?
    public var debugInfo = RedactedDebugInfo()

    public var displayState: PaceState {
        failure == nil ? snapshot?.state ?? .loading : .error
    }

    @ObservationIgnored
    public var onChange: (() -> Void)?

    public init() {}

    public func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        notify()
    }

    public func showLoadingIfNeeded() {
        guard snapshot == nil else {
            return
        }
        failure = nil
        notify()
    }

    public func apply(
        window: CodexLimitWindow,
        snapshot: PaceSnapshot,
        forecast: UsageForecast?,
        debugInfo: RedactedDebugInfo
    ) {
        selectedWindow = window
        self.snapshot = snapshot
        self.forecast = forecast
        failure = nil
        lastCheckedAt = snapshot.fetchedAt
        self.debugInfo = debugInfo
        notify()
    }

    public func applyPaceOnly(snapshot: PaceSnapshot) {
        self.snapshot = snapshot
        notify()
    }

    public func applyError(_ error: Error, staleAfterReset: Bool, executablePath: String?, now: Date = Date()) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if staleAfterReset, let existingSnapshot = snapshot {
            snapshot = PaceSnapshot(
                actualUsedPercent: existingSnapshot.actualUsedPercent,
                remainingPercent: existingSnapshot.remainingPercent,
                idealUsedPercent: existingSnapshot.idealUsedPercent,
                deltaPercentagePoints: existingSnapshot.deltaPercentagePoints,
                usedFraction: existingSnapshot.usedFraction,
                elapsedFraction: existingSnapshot.elapsedFraction,
                resetAt: existingSnapshot.resetAt,
                state: .error,
                fetchedAt: existingSnapshot.fetchedAt,
                isStale: true
            )
        }
        let displayedMessage = staleAfterReset ? PaceError.staleAfterReset(message).errorDescription ?? message : message
        if (error as? PaceError)?.requiresCodexSetup == true {
            failure = .codexSetupRequired(displayedMessage)
        } else {
            failure = .refreshFailed(displayedMessage)
        }
        debugInfo = RedactedDebugInfo(
            executablePath: executablePath,
            appServerStatus: "error",
            lastMethod: "account/rateLimits/read",
            candidates: debugInfo.candidates,
            lastError: displayedMessage,
            generatedAt: now
        )
        notify()
    }

    private func notify() {
        onChange?()
    }
}
