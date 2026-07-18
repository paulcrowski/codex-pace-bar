import CodexPaceBarCore
import Foundation
import Testing

struct CodexSessionLogReaderTests {
    @Test
    func readsOnlyNewCompleteLines() throws {
        let fileURL = try makeLogFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var reader = CodexSessionLogReader()

        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}\n", to: fileURL)
        #expect(try reader.readNewEvents(from: fileURL).count == 1)

        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-1\",\"completed_at\":1784373261,\"duration_ms\":337328}}\n", to: fileURL)
        #expect(try reader.readNewEvents(from: fileURL).count == 1)
        #expect(try reader.readNewEvents(from: fileURL).isEmpty)
    }

    @Test
    func waitsForACompleteLineWhenWriterHasNotFinished() throws {
        let fileURL = try makeLogFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var reader = CodexSessionLogReader()

        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}\n", to: fileURL)
        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",", to: fileURL)
        #expect(try reader.readNewEvents(from: fileURL).count == 1)

        try append("\"turn_id\":\"turn-1\",\"completed_at\":1784373261,\"duration_ms\":337328}}\n", to: fileURL)
        #expect(try reader.readNewEvents(from: fileURL).count == 1)
    }

    @Test
    func resetsAfterLogIsTruncated() throws {
        let fileURL = try makeLogFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var reader = CodexSessionLogReader()

        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}\n", to: fileURL)
        _ = try reader.readNewEvents(from: fileURL)

        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-2\",\"started_at\":1784372924}}\n".utf8)
            .write(to: fileURL)

        let events = try reader.readNewEvents(from: fileURL)
        #expect(events == [.turnStarted(
            turnID: "turn-2",
            startedAt: Date(timeIntervalSince1970: 1784372924)
        )])
    }

    @Test
    func initialBackfillReadsOnlyBoundedTailOfLargeLog() throws {
        let oldEvent = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-old\",\"started_at\":1784372923}}\n"
        let padding = String(repeating: "x", count: 512) + "\n"
        let recentEvent = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-recent\",\"started_at\":1784372924}}\n"
        let fileURL = try makeLogFile(contents: oldEvent + padding + recentEvent)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var reader = CodexSessionLogReader(initialReadLimitBytes: 180)

        let events = try reader.readNewEvents(from: fileURL)

        #expect(events == [.turnStarted(
            turnID: "turn-recent",
            startedAt: Date(timeIntervalSince1970: 1784372924)
        )])
    }

    private func makeLogFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("session.jsonl")
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    private func append(_ text: String, to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
