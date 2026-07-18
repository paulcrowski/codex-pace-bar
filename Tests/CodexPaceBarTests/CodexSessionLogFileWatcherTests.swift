import CodexPaceBarCore
import Foundation
import Testing

struct CodexSessionLogFileWatcherTests {
    @Test
    func deliversEventsWhenLogGrows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("session.jsonl")
        try Data().write(to: fileURL)
        let sink = EventSink()
        let semaphore = DispatchSemaphore(value: 0)
        let watcher = CodexSessionLogFileWatcher(fileURL: fileURL) { events in
            sink.append(events)
            semaphore.signal()
        }

        try watcher.start()
        try append(
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}\n",
            to: fileURL
        )

        #expect(semaphore.wait(timeout: .now() + 1) == .success)
        watcher.stop()
        #expect(sink.events.count == 1)
        #expect(sink.events.first == .turnStarted(
            turnID: "turn-1",
            startedAt: Date(timeIntervalSince1970: 1784372923)
        ))
    }

    @Test
    func rejectsMissingLogFile() {
        let watcher = CodexSessionLogFileWatcher(
            fileURL: URL(fileURLWithPath: "/tmp/codex-pace-bar-missing-session.jsonl"),
            onEvents: { _ in }
        )

        #expect(throws: CodexSessionLogFileWatcherError.openFailed(
            "/tmp/codex-pace-bar-missing-session.jsonl"
        )) {
            try watcher.start()
        }
    }

    private func append(_ text: String, to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}

private final class EventSink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [CodexSessionLogEvent] = []

    func append(_ newEvents: [CodexSessionLogEvent]) {
        lock.lock()
        events.append(contentsOf: newEvents)
        lock.unlock()
    }
}
