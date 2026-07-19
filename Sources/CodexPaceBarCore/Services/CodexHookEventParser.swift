import Foundation

public struct CodexHookEventParser: Sendable {
    public init() {}

    public func parseLine(_ data: Data) -> [CodexSessionLogEvent] {
        guard let input = try? JSONDecoder().decode(Input.self, from: data),
              let sessionID = input.sessionID,
              let turnID = input.turnID,
              let eventName = input.hookEventName
        else {
            return []
        }

        let occurredAt = input.generatedAt.map(Date.init(timeIntervalSince1970:)) ?? Date()
        var events: [CodexSessionLogEvent] = [
            .sessionDiscovered(sessionID: sessionID, workingDirectory: input.workingDirectory),
            .turnContext(
                turnID: turnID,
                model: input.model,
                effort: nil,
                workingDirectory: input.workingDirectory
            ),
            .turnNavigationContext(
                turnID: turnID,
                transcriptPath: input.transcriptPath,
                terminalProgram: input.terminalProgram,
                terminalSessionID: input.terminalSessionID,
                sourceBundleIdentifier: input.sourceBundleIdentifier
            )
        ]

        switch eventName {
        case "UserPromptSubmit":
            events.append(.turnStatusChanged(turnID: turnID, status: .working, occurredAt: occurredAt))
        case "PermissionRequest":
            events.append(.turnStatusChanged(turnID: turnID, status: .needsApproval, occurredAt: occurredAt))
        case "Stop":
            events.append(.turnStatusChanged(turnID: turnID, status: .completed, occurredAt: occurredAt))
        default:
            return []
        }
        return events
    }

    private struct Input: Decodable {
        let sessionID: String?
        let turnID: String?
        let workingDirectory: String?
        let hookEventName: String?
        let model: String?
        let transcriptPath: String?
        let generatedAt: TimeInterval?
        let terminalProgram: String?
        let terminalSessionID: String?
        let sourceBundleIdentifier: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case turnID = "turn_id"
            case workingDirectory = "cwd"
            case hookEventName = "hook_event_name"
            case model
            case transcriptPath = "transcript_path"
            case generatedAt = "generated_at"
            case terminalProgram = "terminal_program"
            case terminalSessionID = "terminal_session_id"
            case sourceBundleIdentifier = "source_bundle_identifier"
        }
    }
}
