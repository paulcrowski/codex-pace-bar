import Foundation

public enum CodexSessionLogEvent: Equatable, Sendable {
    case sessionDiscovered(sessionID: String, workingDirectory: String?)
    case turnContext(
        turnID: String,
        model: String?,
        effort: String?,
        workingDirectory: String?
    )
    case turnStarted(turnID: String, startedAt: Date)
    case turnStatusChanged(turnID: String, status: CodexTaskStatus, occurredAt: Date)
    case currentTurnStatusChanged(status: CodexTaskStatus, occurredAt: Date)
    case turnNavigationContext(
        turnID: String,
        transcriptPath: String?,
        terminalProgram: String?,
        terminalSessionID: String?,
        sourceBundleIdentifier: String?
    )
    case turnCompleted(
        turnID: String,
        completedAt: Date,
        duration: TimeInterval,
        timeToFirstToken: TimeInterval?
    )
}

public enum CodexTaskStatus: String, Codable, Sendable {
    case queued
    case working
    case needsApproval
    case needsInput
    case completed
    case failed
    case cancelled
    case stale

    public var isWaitingForUser: Bool {
        self == .needsApproval || self == .needsInput
    }

    public var isActive: Bool {
        self == .queued || self == .working || isWaitingForUser
    }

    public var isFinished: Bool {
        self == .completed || self == .failed || self == .cancelled || self == .stale
    }
}

public struct CodexTaskActivity: Equatable, Identifiable, Sendable {
    public let sessionID: String
    public let turnID: String
    public var workingDirectory: String?
    public var model: String?
    public var effort: String?
    public var status: CodexTaskStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var duration: TimeInterval?
    public var timeToFirstToken: TimeInterval?
    public var lastEventAt: Date?
    public var waitingStartedAt: Date?
    public var waitingDuration: TimeInterval
    public var transcriptPath: String?
    public var terminalProgram: String?
    public var terminalSessionID: String?
    public var sourceBundleIdentifier: String?

    public var id: String {
        "\(sessionID):\(turnID)"
    }

    public init(
        sessionID: String,
        turnID: String,
        workingDirectory: String?,
        model: String?,
        effort: String?,
        status: CodexTaskStatus,
        startedAt: Date?,
        completedAt: Date?,
        duration: TimeInterval?,
        timeToFirstToken: TimeInterval?,
        lastEventAt: Date? = nil,
        waitingStartedAt: Date? = nil,
        waitingDuration: TimeInterval = 0,
        transcriptPath: String? = nil,
        terminalProgram: String? = nil,
        terminalSessionID: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.workingDirectory = workingDirectory
        self.model = model
        self.effort = effort
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.duration = duration
        self.timeToFirstToken = timeToFirstToken
        self.lastEventAt = lastEventAt
        self.waitingStartedAt = waitingStartedAt
        self.waitingDuration = waitingDuration
        self.transcriptPath = transcriptPath
        self.terminalProgram = terminalProgram
        self.terminalSessionID = terminalSessionID
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}

public struct CodexTaskStatusEvent: Equatable, Sendable {
    public let sessionID: String
    public let turnID: String
    public let status: CodexTaskStatus
    public let occurredAt: Date

    public var taskID: String { "\(sessionID):\(turnID)" }

    public init(sessionID: String, turnID: String, status: CodexTaskStatus, occurredAt: Date) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.status = status
        self.occurredAt = occurredAt
    }
}

public enum CodexDailyWorkRating: String, Codable, CaseIterable, Sendable {
    case calm
    case intense
    case tooMuch
}

public struct CodexDailyWorkCheckIn: Equatable, Sendable {
    public let day: Date
    public let rating: CodexDailyWorkRating
    public let rhythmScore: Int?

    public init(day: Date, rating: CodexDailyWorkRating, rhythmScore: Int? = nil) {
        self.day = day
        self.rating = rating
        self.rhythmScore = rhythmScore
    }
}
