import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var snapshot: PaceSnapshot?
    var selectedWindow: CodexLimitWindow?
    var displayState: PaceState = .loading
    var errorMessage: String?
    var isRefreshing = false
    var lastCheckedAt: Date?
    var debugInfo = RedactedDebugInfo()

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
        displayState = .loading
        errorMessage = nil
        notify()
    }

    func apply(window: CodexLimitWindow, snapshot: PaceSnapshot, debugInfo: RedactedDebugInfo) {
        selectedWindow = window
        self.snapshot = snapshot
        displayState = snapshot.state
        errorMessage = nil
        lastCheckedAt = snapshot.fetchedAt
        self.debugInfo = debugInfo
        notify()
    }

    func applyPaceOnly(snapshot: PaceSnapshot) {
        self.snapshot = snapshot
        displayState = snapshot.state
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
        displayState = .error
        errorMessage = staleAfterReset ? PaceError.staleAfterReset(message).errorDescription : message
        debugInfo = RedactedDebugInfo(
            executablePath: executablePath,
            appServerStatus: "error",
            lastMethod: "account/rateLimits/read",
            candidates: debugInfo.candidates,
            lastError: errorMessage,
            generatedAt: Date()
        )
        notify()
    }

    private func notify() {
        onChange?()
    }
}
