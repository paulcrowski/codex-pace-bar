import CodexPaceBarCore
import Foundation
import Testing

struct CodexHookEventParserTests {
    @Test
    func parsesOnlyMetadataAndMapsPermissionToNeedsApproval() throws {
        let input = """
        {"session_id":"session","turn_id":"turn","cwd":"/work/project","hook_event_name":"PermissionRequest","model":"gpt-5","transcript_path":"/private/transcript.jsonl","generated_at":1784372000,"terminal_program":"Apple_Terminal","terminal_session_id":"window-1","prompt":"secret prompt must be ignored"}
        """
        let events = CodexHookEventParser().parseLine(Data(input.utf8))

        #expect(events.contains(.sessionDiscovered(sessionID: "session", workingDirectory: "/work/project")))
        #expect(events.contains(.turnStatusChanged(
            turnID: "turn",
            status: .needsApproval,
            occurredAt: Date(timeIntervalSince1970: 1_784_372_000)
        )))
        #expect(events.count == 4)
    }

    @Test
    func ignoresUnknownHooksAndContentWithoutIdentifiers() {
        #expect(CodexHookEventParser().parseLine(Data("{\"hook_event_name\":\"Stop\",\"prompt\":\"private\"}".utf8)).isEmpty)
        #expect(CodexHookEventParser().parseLine(Data("{\"session_id\":\"s\",\"turn_id\":\"t\",\"hook_event_name\":\"PostToolUse\"}".utf8)).isEmpty)
    }
}
