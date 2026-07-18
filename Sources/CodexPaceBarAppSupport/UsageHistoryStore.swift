import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
public final class UsageHistoryStore {
    public private(set) var samples: [UsageSample]
    public private(set) var lastPersistenceError: String?

    @ObservationIgnored
    private let repository: UsageHistoryRepository

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        let repository = UsageHistoryRepository(fileURL: fileURL, fileManager: fileManager)
        self.repository = repository
        self.samples = repository.load()
        self.lastPersistenceError = nil
    }

    public var currentSamples: [UsageSample] {
        UsageHistorySeries.current(from: samples, now: Date())
    }

    public func record(window: CodexLimitWindow, at timestamp: Date) {
        let sample = UsageSample(
            timestamp: timestamp,
            usedPercent: window.usedPercent,
            resetAt: window.resetsAt,
            limitId: window.limitId
        )

        do {
            samples = try repository.appending(sample, to: samples)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }
}
