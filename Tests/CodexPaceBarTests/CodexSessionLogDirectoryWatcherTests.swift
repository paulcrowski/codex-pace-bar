import CodexPaceBarCore
import Foundation
import Testing

struct CodexSessionLogDirectoryWatcherTests {
    @Test
    func reportsNewFilesInDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let semaphore = DispatchSemaphore(value: 0)
        let watcher = CodexSessionLogDirectoryWatcher(directoryURL: directory) {
            semaphore.signal()
        }
        try watcher.start()
        try Data("{}\n".utf8).write(to: directory.appendingPathComponent("new-session.jsonl"))

        #expect(semaphore.wait(timeout: .now() + 1) == .success)
        watcher.stop()
    }

    @Test
    func coalescesRapidDirectoryChangesIntoOneRescanSignal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let signal = SignalCounter()
        let watcher = CodexSessionLogDirectoryWatcher(directoryURL: directory) {
            signal.increment()
        }
        try watcher.start()
        for index in 0..<4 {
            try Data("{}\n".utf8)
                .write(to: directory.appendingPathComponent("session-\(index).jsonl"))
        }

        #expect(signal.wait(timeout: .now() + 1) == .success)
        Thread.sleep(forTimeInterval: Self.changeDebounceInterval * 2)
        watcher.stop()
        #expect(signal.value == 1)
    }

    private static let changeDebounceInterval = CodexSessionLogDirectoryWatcher.changeDebounceInterval

    @Test
    func rejectsMissingDirectory() {
        let path = "/tmp/codex-pace-bar-missing-session-directory-\(UUID().uuidString)"
        let watcher = CodexSessionLogDirectoryWatcher(directoryURL: URL(fileURLWithPath: path)) {}

        #expect(throws: CodexSessionLogDirectoryWatcherError.openFailed(path)) {
            try watcher.start()
        }
    }
}

private final class SignalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }
}
