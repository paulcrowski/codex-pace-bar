import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
final class UsageHistoryStore {
    private(set) var samples: [UsageSample]

    @ObservationIgnored
    private let fileURL: URL

    @ObservationIgnored
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.samples = Self.load(from: self.fileURL)
    }

    func record(window: CodexLimitWindow, at timestamp: Date) {
        samples = samples.filter {
            $0.limitId == window.limitId && $0.resetAt == window.resetsAt
        }
        samples.append(
            UsageSample(
                timestamp: timestamp,
                usedPercent: window.usedPercent,
                resetAt: window.resetsAt,
                limitId: window.limitId
            )
        )

        if samples.count > 2_500 {
            samples = Array(samples.suffix(2_500))
        }

        persist()
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(samples)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is optional; a failed write must not interrupt rate-limit refreshes.
        }
    }

    private static func load(from fileURL: URL) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let samples = try? JSONDecoder().decode([UsageSample].self, from: data)
        else {
            return []
        }
        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }
}
