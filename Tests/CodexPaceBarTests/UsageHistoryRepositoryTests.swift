@testable import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct UsageHistoryRepositoryTests {
    @Test
    func missingFilesLoadEmptyHistory() throws {
        try withTemporaryDirectory { directory in
            let repository = repository(in: directory)

            #expect(repository.load().isEmpty)
        }
    }

    @Test
    func firstRecordCreatesPrimaryWithoutInventingBackup() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let backup = backupURL(in: directory)
            let repository = repository(in: directory)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000))

            let persisted = try repository.appending(first, to: [])

            #expect(persisted == [first])
            #expect(decode(primary) == [first])
            #expect(!FileManager.default.fileExists(atPath: backup.path))
        }
    }

    @Test
    func successfulWriteBacksUpPreviousPrimary() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let backup = backupURL(in: directory)
            let repository = repository(in: directory)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            let second = sample(at: date(2_000), used: 11, resetAt: date(10_000))
            let initial = try repository.appending(first, to: [])

            let persisted = try repository.appending(second, to: initial)

            #expect(decode(backup) == [first])
            #expect(decode(primary) == persisted)
            #expect(persisted == [first, second])
        }
    }

    @Test
    func changedResetMetadataAndLimitIdentifierNeverDeleteSamples() throws {
        try withTemporaryDirectory { directory in
            let repository = repository(in: directory)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000), limitId: "rateLimits")
            let second = sample(at: date(2_000), used: 11, resetAt: date(10_052), limitId: "codex")

            let initial = try repository.appending(first, to: [])
            let persisted = try repository.appending(second, to: initial)

            #expect(persisted == [first, second])
        }
    }

    @Test
    func validPrimaryWinsOverOlderBackup() throws {
        try withTemporaryDirectory { directory in
            let primarySample = sample(at: date(2_000), used: 20, resetAt: date(10_000))
            let backupSample = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            try encode([primarySample]).write(to: primaryURL(in: directory), options: .atomic)
            try encode([backupSample]).write(to: backupURL(in: directory), options: .atomic)

            #expect(repository(in: directory).load() == [primarySample])
        }
    }

    @Test
    func validEmptyPrimaryWinsOverNonemptyBackup() throws {
        try withTemporaryDirectory { directory in
            let backupSample = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            try encode([]).write(to: primaryURL(in: directory), options: .atomic)
            try encode([backupSample]).write(to: backupURL(in: directory), options: .atomic)

            #expect(repository(in: directory).load().isEmpty)
        }
    }

    @Test
    func corruptPrimaryRecoversValidBackup() throws {
        try withTemporaryDirectory { directory in
            let backupSample = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            try Data("not-json".utf8).write(to: primaryURL(in: directory))
            try encode([backupSample]).write(to: backupURL(in: directory), options: .atomic)

            #expect(repository(in: directory).load() == [backupSample])
        }
    }

    @Test
    func missingPrimaryRecoversValidBackup() throws {
        try withTemporaryDirectory { directory in
            let backupSample = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            try encode([backupSample]).write(to: backupURL(in: directory), options: .atomic)

            #expect(repository(in: directory).load() == [backupSample])
        }
    }

    @Test
    func recoveredHistoryCanBeAppendedWithoutReplacingGoodBackupWithCorruption() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let backup = backupURL(in: directory)
            let backupSample = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            let next = sample(at: date(2_000), used: 11, resetAt: date(10_000))
            try Data("not-json".utf8).write(to: primary)
            try encode([backupSample]).write(to: backup, options: .atomic)
            let repository = repository(in: directory)

            let recovered = repository.load()
            let persisted = try repository.appending(next, to: recovered)

            #expect(persisted == [backupSample, next])
            #expect(decode(primary) == persisted)
            #expect(decode(backup) == [backupSample])
        }
    }

    @Test
    func corruptPrimaryAndBackupLoadEmptyHistory() throws {
        try withTemporaryDirectory { directory in
            try Data("bad-primary".utf8).write(to: primaryURL(in: directory))
            try Data("bad-backup".utf8).write(to: backupURL(in: directory))

            #expect(repository(in: directory).load().isEmpty)
        }
    }

    @Test
    func corruptPrimaryIsPreservedBeforeStartingNewHistory() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let corrupt = directory.appendingPathComponent("usage-history.corrupt.json")
            let corruptData = Data("not-json".utf8)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            try corruptData.write(to: primary)

            _ = try repository(in: directory).appending(first, to: [])

            #expect(try Data(contentsOf: corrupt) == corruptData)
            #expect(decode(primary) == [first])
        }
    }

    @Test
    func backupFailureLeavesPrimaryUnchanged() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let backup = backupURL(in: directory)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            let second = sample(at: date(2_000), used: 11, resetAt: date(10_000))
            try encode([first]).write(to: primary, options: .atomic)
            let repository = UsageHistoryRepository(
                fileURL: primary,
                backupURL: backup,
                writeData: { data, url in
                    if url == backup {
                        throw TestWriteError.denied
                    }
                    try data.write(to: url, options: .atomic)
                }
            )

            expectWriteFailure {
                _ = try repository.appending(second, to: [first])
            }

            #expect(decode(primary) == [first])
        }
    }

    @Test
    func primaryFailureDoesNotReturnOrPersistCandidate() throws {
        try withTemporaryDirectory { directory in
            let primary = primaryURL(in: directory)
            let backup = backupURL(in: directory)
            let first = sample(at: date(1_000), used: 10, resetAt: date(10_000))
            let second = sample(at: date(2_000), used: 11, resetAt: date(10_000))
            try encode([first]).write(to: primary, options: .atomic)
            let repository = UsageHistoryRepository(
                fileURL: primary,
                backupURL: backup,
                writeData: { data, url in
                    if url == primary {
                        throw TestWriteError.denied
                    }
                    try data.write(to: url, options: .atomic)
                }
            )

            expectWriteFailure {
                _ = try repository.appending(second, to: [first])
            }

            #expect(decode(primary) == [first])
            #expect(decode(backup) == [first])
        }
    }

    @Test
    func retentionRemovesOnlySamplesOlderThanThirtyDays() throws {
        try withTemporaryDirectory { directory in
            let repository = repository(in: directory)
            let newestDate = date(40 * day)
            let expired = sample(at: newestDate.addingTimeInterval(-30 * day - 1), used: 1, resetAt: date(100 * day))
            let boundary = sample(at: newestDate.addingTimeInterval(-30 * day), used: 2, resetAt: date(100 * day))
            let recent = sample(at: newestDate.addingTimeInterval(-day), used: 3, resetAt: date(100 * day))
            let newest = sample(at: newestDate, used: 4, resetAt: date(100 * day))

            let persisted = try repository.appending(newest, to: [expired, boundary, recent])

            #expect(persisted == [boundary, recent, newest])
        }
    }

    @Test
    func moreThanTwoThousandFiveHundredRecentSamplesAreRetained() throws {
        try withTemporaryDirectory { directory in
            let repository = repository(in: directory)
            let resetAt = date(1_000_000)
            let samples = (0..<2_501).map { index in
                sample(at: date(TimeInterval(index)), used: Double(index % 100), resetAt: resetAt)
            }
            let newest = sample(at: date(2_501), used: 1, resetAt: resetAt)

            let persisted = try repository.appending(newest, to: samples)

            #expect(persisted.count == 2_502)
        }
    }

    @Test
    func restartLoadsSameArchiveAndDerivesSameCurrentSeries() throws {
        try withTemporaryDirectory { directory in
            let historyRepository = repository(in: directory)
            let resetAt = date(100_000)
            let first = sample(at: date(1_000), used: 70, resetAt: resetAt)
            let second = sample(at: date(2_000), used: 3, resetAt: resetAt)
            let third = sample(at: date(3_000), used: 4, resetAt: resetAt)
            let initial = try historyRepository.appending(first, to: [])
            let afterReset = try historyRepository.appending(second, to: initial)
            let persisted = try historyRepository.appending(third, to: afterReset)

            let loaded = repository(in: directory).load()

            #expect(loaded == persisted)
            #expect(UsageHistorySeries.current(from: loaded, now: date(3_000)) == [second, third])
        }
    }

    private let day: TimeInterval = 24 * 60 * 60

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func repository(in directory: URL) -> UsageHistoryRepository {
        UsageHistoryRepository(fileURL: primaryURL(in: directory))
    }

    private func primaryURL(in directory: URL) -> URL {
        directory.appendingPathComponent("usage-history.json")
    }

    private func backupURL(in directory: URL) -> URL {
        directory.appendingPathComponent("usage-history.backup.json")
    }

    private func encode(_ samples: [UsageSample]) throws -> Data {
        try JSONEncoder().encode(samples)
    }

    private func decode(_ url: URL) -> [UsageSample]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode([UsageSample].self, from: data)
    }

    private func expectWriteFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected persistence to fail")
        } catch {}
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(
        at timestamp: Date,
        used: Double,
        resetAt: Date,
        limitId: String = "codex"
    ) -> UsageSample {
        UsageSample(timestamp: timestamp, usedPercent: used, resetAt: resetAt, limitId: limitId)
    }
}

private enum TestWriteError: Error {
    case denied
}
