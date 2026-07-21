import CodexPaceBarCore
import Foundation
import Testing

struct CodexSessionLogParserTests {
    @Test
    func acceptsRealIsoTimestampWithoutReadingMessageContent() {
        let line = """
        {"timestamp":"2026-07-18T13:32:41.871Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn","started_at":1784381561,"last_agent_message":"private"}}
        """
        #expect(CodexSessionLogParser().parseLine(line) == .turnStarted(
            turnID: "turn",
            startedAt: Date(timeIntervalSince1970: 1_784_381_561)
        ))
    }

    @Test
    func detectsQuestionAndResumeFromResponseItemsWithoutPromptText() {
        let question = """
        {"timestamp":"2026-07-18T13:32:41Z","type":"response_item","payload":{"type":"custom_tool_call","name":"request_user_input","arguments":"private question"}}
        """
        let answer = """
        {"timestamp":"2026-07-18T13:33:41Z","type":"response_item","payload":{"type":"custom_tool_call_output","output":"private answer"}}
        """
        #expect(CodexSessionLogParser().parseLine(question) == .currentTurnStatusChanged(
            status: .needsInput,
            occurredAt: ISO8601DateFormatter().date(from: "2026-07-18T13:32:41Z")!
        ))
        #expect(CodexSessionLogParser().parseLine(answer) == .currentTurnStatusChanged(
            status: .working,
            occurredAt: ISO8601DateFormatter().date(from: "2026-07-18T13:33:41Z")!
        ))
    }

    private let parser = CodexSessionLogParser()

    @Test
    func parsesSessionMetadataWithoutPromptContent() throws {
        let event = parser.parseLine(#"{"type":"session_meta","payload":{"id":"session-1","session_id":"session-1","cwd":"/work/project","source":"vscode"}}"#)

        #expect(event == .sessionDiscovered(
            sessionID: "session-1",
            workingDirectory: "/work/project"
        ))
    }

    @Test
    func parsesTurnContext() throws {
        let event = parser.parseLine(#"{"type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.6","effort":"high","cwd":"/work/project"}}"#)

        #expect(event == .turnContext(
            turnID: "turn-1",
            model: "gpt-5.6",
            effort: "high",
            workingDirectory: "/work/project"
        ))
    }

    @Test
    func parsesTaskStartAndCompletionTimes() throws {
        let startedAt = Date(timeIntervalSince1970: 1_784_372_923)
        let completedAt = Date(timeIntervalSince1970: 1_784_373_261)

        let started = parser.parseLine(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","started_at":1784372923}}"#)
        let completed = parser.parseLine(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","started_at":1784372923,"completed_at":1784373261,"duration_ms":337328,"time_to_first_token_ms":4589}}"#)

        #expect(started == .turnStarted(turnID: "turn-1", startedAt: startedAt))
        #expect(completed == .turnCompleted(
            turnID: "turn-1",
            completedAt: completedAt,
            duration: 337.328,
            timeToFirstToken: 4.589
        ))
    }

    @Test
    func parsesAbortedTurnAsFinished() throws {
        let completedAt = Date(timeIntervalSince1970: 1_784_373_261)

        let aborted = parser.parseLine(#"{"timestamp":"2026-07-18T13:40:00Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1","reason":"interrupted","completed_at":1784373261,"duration_ms":337328}}"#)

        #expect(aborted == .turnStatusChanged(
            turnID: "turn-1",
            status: .cancelled,
            occurredAt: completedAt
        ))
    }

    @Test
    func ignoresUserContentAndUnknownEvents() throws {
        let userMessage = parser.parseLine(#"{"type":"event_msg","payload":{"type":"user_message","text":"secret prompt"}}"#)
        let unknown = parser.parseLine(#"{"type":"event_msg","payload":{"type":"future_event","text":"secret"}}"#)
        let malformed = parser.parseLine("not-json")

        #expect(userMessage == nil)
        #expect(unknown == nil)
        #expect(malformed == nil)
    }
}
