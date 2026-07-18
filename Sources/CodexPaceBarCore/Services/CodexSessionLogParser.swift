import Foundation

public struct CodexSessionLogParser: Sendable {
    public init() {}

    public func parseLine(_ line: String) -> CodexSessionLogEvent? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        return parseLine(data)
    }

    public func parseLine(_ data: Data) -> CodexSessionLogEvent? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }

        switch envelope.type {
        case "session_meta":
            guard let sessionID = envelope.payload.sessionID ?? envelope.payload.id else {
                return nil
            }
            return .sessionDiscovered(
                sessionID: sessionID,
                workingDirectory: envelope.payload.workingDirectory
            )

        case "turn_context":
            guard let turnID = envelope.payload.turnID else {
                return nil
            }
            return .turnContext(
                turnID: turnID,
                model: envelope.payload.model,
                effort: envelope.payload.effort,
                workingDirectory: envelope.payload.workingDirectory
            )

        case "event_msg":
            return parseEventMessage(envelope.payload, timestamp: envelope.timestamp)

        case "response_item":
            guard let timestamp = envelope.timestamp else { return nil }
            if (envelope.payload.type == "function_call" || envelope.payload.type == "custom_tool_call"),
               envelope.payload.name == "request_user_input" {
                return .currentTurnStatusChanged(status: .needsInput, occurredAt: timestamp)
            }
            if envelope.payload.type == "function_call_output"
                || envelope.payload.type == "custom_tool_call_output" {
                return .currentTurnStatusChanged(status: .working, occurredAt: timestamp)
            }
            return nil

        default:
            return nil
        }
    }

    private func parseEventMessage(_ payload: Payload, timestamp: Date?) -> CodexSessionLogEvent? {
        guard let eventType = payload.type,
              let turnID = payload.turnID
        else {
            return nil
        }

        switch eventType {
        case "task_started":
            guard let startedAt = payload.startedAt else {
                return nil
            }
            return .turnStarted(
                turnID: turnID,
                startedAt: Date(timeIntervalSince1970: startedAt)
            )

        case "task_complete":
            guard let completedAt = payload.completedAt,
                  let durationMilliseconds = payload.durationMilliseconds
            else {
                return nil
            }
            return .turnCompleted(
                turnID: turnID,
                completedAt: Date(timeIntervalSince1970: completedAt),
                duration: durationMilliseconds / 1_000,
                timeToFirstToken: payload.timeToFirstTokenMilliseconds.map { $0 / 1_000 }
            )

        case "task_failed", "turn_failed":
            return .turnStatusChanged(
                turnID: turnID,
                status: .failed,
                occurredAt: payload.completedAt.map(Date.init(timeIntervalSince1970:)) ?? timestamp ?? Date()
            )

        case "task_cancelled", "turn_aborted":
            return .turnStatusChanged(
                turnID: turnID,
                status: .cancelled,
                occurredAt: payload.completedAt.map(Date.init(timeIntervalSince1970:)) ?? timestamp ?? Date()
            )

        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let payload: Payload
        let timestamp: Date?

        enum CodingKeys: String, CodingKey { case type, payload, timestamp }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            payload = try container.decode(Payload.self, forKey: .payload)
            if let seconds = try? container.decode(TimeInterval.self, forKey: .timestamp) {
                timestamp = Date(timeIntervalSince1970: seconds)
            } else if let value = try? container.decode(String.self, forKey: .timestamp) {
                timestamp = ISO8601DateFormatter().date(from: value)
            } else {
                timestamp = nil
            }
        }
    }

    private struct Payload: Decodable {
        let type: String?
        let id: String?
        let sessionID: String?
        let workingDirectory: String?
        let turnID: String?
        let model: String?
        let effort: String?
        let startedAt: TimeInterval?
        let completedAt: TimeInterval?
        let durationMilliseconds: TimeInterval?
        let timeToFirstTokenMilliseconds: TimeInterval?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case type
            case id
            case sessionID = "session_id"
            case workingDirectory = "cwd"
            case turnID = "turn_id"
            case model
            case effort
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case durationMilliseconds = "duration_ms"
            case timeToFirstTokenMilliseconds = "time_to_first_token_ms"
            case name
        }
    }
}
