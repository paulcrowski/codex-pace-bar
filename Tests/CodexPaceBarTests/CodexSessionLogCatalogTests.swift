import CodexPaceBarCore
import Foundation
import Testing

struct CodexSessionLogCatalogTests {
    @Test
    func extractsSessionIDFromRolloutFilename() {
        let catalog = CodexSessionLogCatalog()
        let fileURL = URL(fileURLWithPath: "/tmp/rollout-2026-07-18T10-00-00-019f74ea-0cc5-7da2-8239-ffa5eec7f3af.jsonl")

        #expect(catalog.sessionID(for: fileURL) == "019f74ea-0cc5-7da2-8239-ffa5eec7f3af")
        #expect(catalog.sessionID(for: URL(fileURLWithPath: "/tmp/session.jsonl")) == nil)
    }

    @Test
    func returnsRecentJsonlFilesNewestFirstWithinLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let older = directory.appendingPathComponent("older.jsonl")
        let newest = directory.appendingPathComponent("newest.jsonl")
        let ignored = directory.appendingPathComponent("notes.txt")
        try Data().write(to: older)
        try Data().write(to: newest)
        try Data().write(to: ignored)
        try setModificationDate(now.addingTimeInterval(-100), for: older)
        try setModificationDate(now.addingTimeInterval(-10), for: newest)
        try setModificationDate(now.addingTimeInterval(-1), for: ignored)

        let files = try CodexSessionLogCatalog(rootURL: directory)
            .recentLogFiles(limit: 1, now: now, maximumAge: 1_000)

        #expect(files.count == 1)
        #expect(files.first?.resolvingSymlinksInPath() == newest.resolvingSymlinksInPath())
    }

    @Test
    func ignoresLogsOutsideRetentionWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_784_373_500)
        let oldLog = directory.appendingPathComponent("old.jsonl")
        try Data().write(to: oldLog)
        try setModificationDate(now.addingTimeInterval(-10_001), for: oldLog)

        let files = try CodexSessionLogCatalog(rootURL: directory)
            .recentLogFiles(limit: 10, now: now, maximumAge: 10_000)

        #expect(files.isEmpty)
    }

    @Test
    func defaultLimitBoundsStartupWork() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_784_373_500)
        for index in 0..<(CodexSessionLogCatalog.defaultFileLimit + 5) {
            let log = directory.appendingPathComponent("session-\(index).jsonl")
            try Data().write(to: log)
            try setModificationDate(now.addingTimeInterval(TimeInterval(-index)), for: log)
        }

        let files = try CodexSessionLogCatalog(rootURL: directory)
            .recentLogFiles(now: now, maximumAge: 1_000)

        #expect(files.count == CodexSessionLogCatalog.defaultFileLimit)
    }

    @Test
    func keepsOversizedRecentLogsForBoundedTailReading() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oversized = directory.appendingPathComponent("oversized.jsonl")
        try Data(repeating: 0x20, count: 128).write(to: oversized)
        let files = try CodexSessionLogCatalog(rootURL: directory)
            .recentLogFiles(now: Date(), maximumAge: 60, maximumFileSize: 64)

        #expect(files.count == 1)
        #expect(files.first?.resolvingSymlinksInPath() == oversized.resolvingSymlinksInPath())
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}
