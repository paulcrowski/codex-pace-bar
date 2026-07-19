import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Testing

@MainActor
struct TaskMonitorCoordinatorTests {
    @Test
    func receivesSanitizedHookEventsWithoutPolling() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let hookFile = directory.appendingPathComponent("hook-events.jsonl")
        FileManager.default.createFile(atPath: hookFile.path, contents: nil)
        let coordinator = try TaskMonitorCoordinator(
            catalog: CodexSessionLogCatalog(rootURL: sessions),
            databaseURL: directory.appendingPathComponent("tasks.sqlite"),
            hookEventURL: hookFile
        )
        try coordinator.start()
        defer { coordinator.stop() }

        let line = "{\"session_id\":\"session\",\"turn_id\":\"turn\",\"cwd\":\"/work/project\",\"hook_event_name\":\"PermissionRequest\",\"generated_at\":1784372000}\n"
        let handle = try FileHandle(forWritingTo: hookFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()

        var status: CodexTaskStatus?
        for _ in 0..<30 {
            status = try await coordinator.tasks().first?.status
            if status == .needsApproval { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(status == .needsApproval)
    }

    @Test
    func startsFromRecentLogAndPublishesTaskMetadata() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("session.jsonl")
        let contents = [
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session-1\",\"session_id\":\"session-1\",\"cwd\":\"/work/project\"}}",
            "{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"turn-1\",\"model\":\"gpt-5.6\",\"effort\":\"high\",\"cwd\":\"/work/project\"}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-1\",\"completed_at\":1784373261,\"duration_ms\":337328}}"
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: logURL)

        var reader = CodexSessionLogReader()
        #expect(try reader.readNewEvents(from: logURL).count == 4)

        let catalog = CodexSessionLogCatalog(rootURL: directory)
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let coordinator = try TaskMonitorCoordinator(catalog: catalog, databaseURL: databaseURL)
        try coordinator.start()

        var tasks: [CodexTaskActivity] = []
        for _ in 0..<20 {
            tasks = try await coordinator.tasks()
            if tasks.first?.status == .completed {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        coordinator.stop()

        #expect(tasks.count == 1)
        #expect(tasks.first?.sessionID == "session-1")
        #expect(tasks.first?.status == .completed)
        #expect(tasks.first?.model == "gpt-5.6")
    }

    @Test
    func stopClosesWatchersAndStopsReceivingEvents() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("session.jsonl")
        try Data().write(to: logURL)
        let coordinator = try TaskMonitorCoordinator(
            catalog: CodexSessionLogCatalog(rootURL: directory),
            databaseURL: directory.appendingPathComponent("tasks.sqlite")
        )
        try coordinator.start()
        coordinator.stop()

        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1784372923}}\n", to: logURL)
        try await Task.sleep(for: .milliseconds(50))

        #expect(try await coordinator.tasks().isEmpty)
    }

    @Test
    func discoversNewSessionFileWithoutManualRescan() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let coordinator = try TaskMonitorCoordinator(
            catalog: CodexSessionLogCatalog(rootURL: directory),
            databaseURL: directory.appendingPathComponent("tasks.sqlite")
        )
        try coordinator.start()

        let logURL = directory.appendingPathComponent("new-session.jsonl")
        let contents = [
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session-new\",\"cwd\":\"/work/new\"}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-new\",\"started_at\":1784372923}}"
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: logURL)

        var tasks: [CodexTaskActivity] = []
        for _ in 0..<20 {
            tasks = try await coordinator.tasks()
            if tasks.first?.turnID == "turn-new" {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        coordinator.stop()

        #expect(tasks.count == 1)
        #expect(tasks.first?.status == .working)
        #expect(tasks.first?.workingDirectory == "/work/new")
    }

    @Test
    func discoversNewSessionFileInNestedDayDirectoryWithoutManualRescan() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        let dayDirectory = sessions
            .appendingPathComponent("2026")
            .appendingPathComponent("07")
            .appendingPathComponent("18")
        try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)

        let existingLog = dayDirectory.appendingPathComponent("existing-session.jsonl")
        let existingContents = [
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session-existing\",\"cwd\":\"/work/existing\"}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-existing\",\"started_at\":1784372900}}"
        ].joined(separator: "\n") + "\n"
        try Data(existingContents.utf8).write(to: existingLog)

        let coordinator = try TaskMonitorCoordinator(
            catalog: CodexSessionLogCatalog(rootURL: sessions),
            databaseURL: directory.appendingPathComponent("tasks.sqlite")
        )
        try coordinator.start()
        defer { coordinator.stop() }

        let newLog = dayDirectory.appendingPathComponent("new-session.jsonl")
        let contents = [
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session-new\",\"cwd\":\"/work/new\"}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-new\",\"started_at\":1784372923}}"
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: newLog)

        var tasks: [CodexTaskActivity] = []
        for _ in 0..<30 {
            tasks = try await coordinator.tasks()
            if tasks.contains(where: { $0.turnID == "turn-new" }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(tasks.filter { $0.status == .working }.count == 2)
        #expect(Set(tasks.map(\.turnID)) == ["turn-existing", "turn-new"])
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func append(_ text: String, to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
