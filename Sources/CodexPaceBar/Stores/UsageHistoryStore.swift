import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class UsageHistoryStore {
    private(set) var samples: [UsageSample]

    @ObservationIgnored
    private let repository: UsageHistoryRepository

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        let repository = UsageHistoryRepository(fileURL: fileURL, fileManager: fileManager)
        self.repository = repository
        self.samples = repository.load()
    }

    var currentSamples: [UsageSample] {
        UsageHistorySeries.current(from: samples, now: Date())
    }

    func record(window: CodexLimitWindow, at timestamp: Date) {
        let sample = UsageSample(
            timestamp: timestamp,
            usedPercent: window.usedPercent,
            resetAt: window.resetsAt,
            limitId: window.limitId
        )

        do {
            samples = try repository.appending(sample, to: samples)
        } catch {
            // History is optional; failed persistence must not interrupt rate-limit refreshes.
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }
}
