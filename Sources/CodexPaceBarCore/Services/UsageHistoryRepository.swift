import Foundation

public struct UsageHistoryRepository {
    public static let retentionDuration: TimeInterval = 30 * 24 * 60 * 60

    private let fileURL: URL
    private let backupURL: URL
    private let corruptURL: URL
    private let retainedDuration: TimeInterval
    private let fileManager: FileManager
    private let writeData: (Data, URL) throws -> Void

    public init(
        fileURL: URL,
        backupURL: URL? = nil,
        retainedDuration: TimeInterval = Self.retentionDuration,
        fileManager: FileManager = .default
    ) {
        self.init(
            fileURL: fileURL,
            backupURL: backupURL ?? Self.defaultBackupURL(for: fileURL),
            retainedDuration: retainedDuration,
            fileManager: fileManager,
            writeData: { data, url in
                try data.write(to: url, options: .atomic)
            }
        )
    }

    init(
        fileURL: URL,
        backupURL: URL,
        retainedDuration: TimeInterval = Self.retentionDuration,
        fileManager: FileManager = .default,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.backupURL = backupURL
        self.corruptURL = Self.defaultCorruptURL(for: fileURL)
        self.retainedDuration = retainedDuration
        self.fileManager = fileManager
        self.writeData = writeData
    }

    public func load() -> [UsageSample] {
        if let samples = decodedSamples(at: fileURL) {
            return samples.sorted { $0.timestamp < $1.timestamp }
        }
        if let samples = decodedSamples(at: backupURL) {
            return samples.sorted { $0.timestamp < $1.timestamp }
        }
        return []
    }

    public func appending(_ sample: UsageSample, to samples: [UsageSample]) throws -> [UsageSample] {
        let newestTimestamp = max(sample.timestamp, samples.map(\.timestamp).max() ?? sample.timestamp)
        let retentionCutoff = newestTimestamp.addingTimeInterval(-retainedDuration)
        let retainedSamples = samples.filter { $0.timestamp >= retentionCutoff }
        let candidate = (retainedSamples + [sample]).sorted { $0.timestamp < $1.timestamp }

        guard candidate.count == retainedSamples.count + 1 else {
            throw UsageHistoryRepositoryError.unexpectedSampleLoss
        }

        let candidateData = try JSONEncoder().encode(candidate)
        guard let validatedCandidate = try? JSONDecoder().decode([UsageSample].self, from: candidateData),
              validatedCandidate == candidate
        else {
            throw UsageHistoryRepositoryError.validationFailed
        }

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let currentData = try? Data(contentsOf: fileURL) {
            if (try? JSONDecoder().decode([UsageSample].self, from: currentData)) != nil {
                try writeData(currentData, backupURL)
            } else {
                try? writeData(currentData, corruptURL)
            }
        }

        try writeData(candidateData, fileURL)
        return candidate
    }

    private func decodedSamples(at url: URL) -> [UsageSample]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode([UsageSample].self, from: data)
    }

    private static func defaultBackupURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("usage-history.backup.json")
    }

    private static func defaultCorruptURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("usage-history.corrupt.json")
    }
}

public enum UsageHistoryRepositoryError: LocalizedError, Equatable {
    case unexpectedSampleLoss
    case validationFailed

    public var errorDescription: String? {
        switch self {
        case .unexpectedSampleLoss:
            return "Usage history update would have lost an existing sample."
        case .validationFailed:
            return "Usage history validation failed before writing the file."
        }
    }
}
