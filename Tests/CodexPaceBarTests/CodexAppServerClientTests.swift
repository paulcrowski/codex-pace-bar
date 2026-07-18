import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct CodexAppServerClientTests {
    @Test
    func sendsRequestsAndCorrelatesResponses() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        let result = try await client.request(method: "echo", timeoutSeconds: 1)

        #expect(result["ok"] == .bool(true))
    }

    @Test
    func publishesServerNotificationsSeparatelyFromResponses() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        let stream = await client.notifications()
        let notificationTask = Task {
            for await notification in stream {
                return notification
            }
            return nil
        }

        let result = try await client.request(method: "notify", timeoutSeconds: 1)
        let notification = await notificationTask.value

        #expect(result["ok"] == .bool(true))
        #expect(notification?.method == "turn/started")
        #expect(notification?.params?["threadId"] == .string("thread-1"))
    }

    @Test
    func timesOutAndRemainsUsable() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        do {
            _ = try await client.request(method: "hang", timeoutSeconds: 0.05)
            Issue.record("Expected request to time out.")
        } catch let error as PaceError {
            #expect(error == .appServerTimeout("hang"))
        }

        let result = try await client.request(method: "echo", timeoutSeconds: 1)
        #expect(result["ok"] == .bool(true))
    }

    @Test
    func cancellationRemovesPendingRequest() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        try await client.ensureInitialized()
        let request = Task {
            try await client.request(method: "hang", timeoutSeconds: 5)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        request.cancel()

        do {
            _ = try await request.value
            Issue.record("Expected request cancellation.")
        } catch is CancellationError {
            // Expected.
        }

        let result = try await client.request(method: "echo", timeoutSeconds: 1)
        #expect(result["ok"] == .bool(true))
    }

    @Test
    func malformedResponseFailsImmediately() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        try await client.ensureInitialized()
        do {
            _ = try await client.request(method: "malformed", timeoutSeconds: 1)
            Issue.record("Expected malformed response to fail.")
        } catch PaceError.jsonDecodingFailed(let reason) {
            #expect(!reason.isEmpty)
        }
    }

    @Test
    func processExitFailsPendingRequest() async throws {
        let fixture = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = CodexAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        try await client.ensureInitialized()
        do {
            _ = try await client.request(method: "exit", timeoutSeconds: 1)
            Issue.record("Expected process exit.")
        } catch let error as PaceError {
            #expect(error == .appServerExited(7))
        }
    }

    private func makeFakeServer() throws -> (root: URL, executable: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerClientTests")
            .appendingPathComponent(UUID().uuidString)
        let executable = root.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let script = #"""
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s\n' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"echo"'*)
              printf '{"id":%s,"result":{"ok":true}}\n' "$id"
              ;;
            *'"method":"notify"'*)
              printf '{"method":"turn/started","params":{"threadId":"thread-1"}}\n'
              printf '{"id":%s,"result":{"ok":true}}\n' "$id"
              ;;
            *'"method":"malformed"'*)
              printf 'not json\n'
              ;;
            *'"method":"exit"'*)
              exit 7
              ;;
            *'"method":"hang"'*)
              ;;
          esac
        done
        """#

        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable)
    }
}
