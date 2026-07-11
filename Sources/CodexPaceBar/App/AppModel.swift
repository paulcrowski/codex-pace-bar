import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Failure: Equatable {
        case codexSetupRequired(String)
        case refreshFailed(String)

        var message: String {
            switch self {
            case let .codexSetupRequired(message), let .refreshFailed(message):
                return message
            }
        }

        var requiresCodexSetup: Bool {
            if case .codexSetupRequired = self {
                return true
            }
            return false
        }
    }

    var snapshot: PaceSnapshot?
    var selectedWindow: CodexLimitWindow?
    var forecast: UsageForecast?
    var failure: Failure?
    var isRefreshing = false
    var lastCheckedAt: Date?
    var debugInfo = RedactedDebugInfo()

    var displayState: PaceState {
        failure == nil ? snapshot?.state ?? .loading : .error
    }

    @ObservationIgnored
    var onChange: (() -> Void)?

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        notify()
    }

    func showLoadingIfNeeded() {
        guard snapshot == nil else {
            return
        }
        failure = nil
        notify()
    }

    func apply(
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

    func applyPaceOnly(snapshot: PaceSnapshot) {
        self.snapshot = snapshot
        notify()
    }

    func applyError(_ error: Error, staleAfterReset: Bool, executablePath: String?) {
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
            generatedAt: Date()
        )
        notify()
    }

    private func notify() {
        onChange?()
    }
}
