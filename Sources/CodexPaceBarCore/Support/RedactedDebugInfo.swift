import Foundation

public struct RedactedDebugInfo: Equatable, Sendable {
    public var executablePath: String?
    public var appServerStatus: String
    public var lastMethod: String?
    public var selectedSource: String?
    public var candidates: [RateLimitCandidate]
    public var lastError: String?
    public var generatedAt: Date

    public init(
        executablePath: String? = nil,
        appServerStatus: String = "not started",
        lastMethod: String? = nil,
        selectedSource: String? = nil,
        candidates: [RateLimitCandidate] = [],
        lastError: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.executablePath = executablePath
        self.appServerStatus = appServerStatus
        self.lastMethod = lastMethod
        self.selectedSource = selectedSource
        self.candidates = candidates
        self.lastError = lastError
        self.generatedAt = generatedAt
    }

    public var redactedText: String {
        var lines = [
            "Codex Pace Bar Debug Info",
            "Generated: \(Self.format(generatedAt))",
            "Executable path: \(executablePath ?? "not resolved")",
            "App-server status: \(appServerStatus)"
        ]

        if let lastMethod {
            lines.append("Last method: \(lastMethod)")
        }

        if let selectedSource {
            lines.append("Selected source: \(selectedSource)")
        }

        if !candidates.isEmpty {
            lines.append("Detected windows:")
            for candidate in candidates {
                let limitId = candidate.limitId ?? "nil"
                let duration = candidate.windowDurationMins.map { String(Int($0)) } ?? "nil"
                let used = candidate.usedPercent.map { String(format: "%.0f", $0) } ?? "nil"
                lines.append("- \(candidate.source).\(candidate.kind) limitId=\(limitId) usedPercent=\(used) windowDurationMins=\(duration) hasResetsAt=\(candidate.hasResetsAt)")
            }
        }

        if let lastError {
            lines.append("Last error: \(lastError)")
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
