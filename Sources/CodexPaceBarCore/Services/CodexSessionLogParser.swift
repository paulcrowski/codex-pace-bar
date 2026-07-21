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
            let resolvedTurnID = envelope.payload.turnID ?? envelope.metadata?.turnID
            if let features = parsePlanFeatures(from: envelope.payload) {
                return .turnPlanObserved(
                    turnID: resolvedTurnID,
                    observedAt: timestamp,
                    features: features
                )
            }
            if (envelope.payload.type == "function_call" || envelope.payload.type == "custom_tool_call"),
               envelope.payload.name == "spawn_agent" {
                return .swarmAgentSpawned(occurredAt: timestamp)
            }
            if (envelope.payload.type == "function_call" || envelope.payload.type == "custom_tool_call"),
               envelope.payload.name == "request_user_input" {
                return .currentTurnStatusChanged(status: .needsInput, occurredAt: timestamp)
            }
            if envelope.payload.type == "function_call_output"
                || envelope.payload.type == "custom_tool_call_output" {
                let outputText = envelope.payload.output?.text ?? ""
                if let goal = parseGoal(from: outputText) {
                    return .goalUpdated(goal)
                }
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
        guard let eventType = payload.type else {
            return nil
        }

        if eventType == "thread_goal_updated",
           let goal = payload.goal,
           let activity = goal.activity {
            return .goalUpdated(activity)
        }

        guard let turnID = payload.turnID else {
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

    private func parseGoal(from output: String) -> CodexGoalActivity? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let start = line.firstIndex(of: "{") else { continue }
            let candidate = String(line[start...])
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let goalObject = object["goal"] as? [String: Any],
                  let goalData = try? JSONSerialization.data(withJSONObject: goalObject),
                  let goal = try? JSONDecoder().decode(GoalPayload.self, from: goalData)
            else { continue }
            return goal.activity
        }
        return nil
    }

    private func parsePlanFeatures(from payload: Payload) -> CodexTaskPlanFeatures? {
        guard let input = payload.input,
              payload.name == "update_plan" || (payload.name == "exec" && input.contains("update_plan"))
        else { return nil }
        let object = extractJSONObject(from: input) ?? (try? JSONSerialization.jsonObject(with: Data(input.utf8)))
        guard let object else { return nil }
        return CodexTaskPlanFeatureExtractor().features(from: object)
    }

    private func extractJSONObject(from source: String) -> Any? {
        guard let marker = source.range(of: "update_plan") else { return nil }
        let suffix = source[marker.upperBound...]
        guard let opening = suffix.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        var index = opening
        while index < suffix.endIndex {
            let character = suffix[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = suffix.index(after: index)
                    break
                }
            }
            index = suffix.index(after: index)
        }
        guard let end,
              let data = String(suffix[opening..<end]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private struct Envelope: Decodable {
        let type: String
        let payload: Payload
        let timestamp: Date?
        let metadata: Metadata?

        enum CodingKeys: String, CodingKey {
            case type, payload, timestamp
            case metadata = "internal_chat_message_metadata_passthrough"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            payload = try container.decode(Payload.self, forKey: .payload)
            metadata = try? container.decode(Metadata.self, forKey: .metadata)
            if let seconds = try? container.decode(TimeInterval.self, forKey: .timestamp) {
                timestamp = Date(timeIntervalSince1970: seconds)
            } else if let value = try? container.decode(String.self, forKey: .timestamp) {
                timestamp = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
                    ?? (try? Date.ISO8601FormatStyle().parse(value))
            } else {
                timestamp = nil
            }
        }
    }

    private struct Metadata: Decodable {
        let turnID: String?

        enum CodingKeys: String, CodingKey { case turnID = "turn_id" }
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
        let input: String?
        let output: OutputValue?
        let goal: GoalPayload?

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
            case input
            case output
            case goal
        }
    }

    private enum OutputValue: Decodable {
        case text(String)
        case parts([OutputPart])

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(value)
            } else {
                self = .parts(try decoder.singleValueContainer().decode([OutputPart].self))
            }
        }

        var text: String {
            switch self {
            case let .text(value): value
            case let .parts(parts): parts.compactMap(\.text).joined(separator: "\n")
            }
        }
    }

    private struct OutputPart: Decodable {
        let text: String?
    }

    private struct GoalPayload: Decodable {
        let threadID: String
        let createdAt: TimeInterval
        let updatedAt: TimeInterval
        let status: CodexGoalStatus
        let timeUsedSeconds: TimeInterval

        enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case createdAt
            case updatedAt
            case status
            case timeUsedSeconds
        }

        var activity: CodexGoalActivity? {
            guard threadID.isEmpty == false,
                  createdAt.isFinite,
                  updatedAt.isFinite,
                  timeUsedSeconds.isFinite,
                  updatedAt >= createdAt,
                  timeUsedSeconds >= 0
            else { return nil }
            return CodexGoalActivity(
                threadID: threadID,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                status: status,
                activeDuration: timeUsedSeconds
            )
        }
    }
}
