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
    case turnPlanObserved(
        turnID: String?,
        observedAt: Date,
        features: CodexTaskPlanFeatures
    )
    case goalUpdated(CodexGoalActivity)
    case swarmAgentSpawned(occurredAt: Date)
}

public enum CodexTaskCategory: String, Codable, Sendable {
    case question
    case smallFix = "small_fix"
    case feature
    case audit
    case research
    case dataAnalysis = "data_analysis"
    case release
    case unknown
}

public enum CodexTaskComplexity: String, Codable, Sendable {
    case simple
    case medium
    case complex
    case veryComplex = "very_complex"
    case unknown
}

public struct CodexTaskPlanFeatures: Codable, Equatable, Sendable {
    public let stepCount: Int
    public let workUnitCount: Int
    public let verificationCount: Int
    public let buildCount: Int
    public let runtimeCheckCount: Int
    public let repositoryCount: Int
    public let plannedParallelism: Int
    public let category: CodexTaskCategory
    public let complexity: CodexTaskComplexity
    public let classifierVersion: Int

    public init(
        stepCount: Int,
        workUnitCount: Int,
        verificationCount: Int,
        buildCount: Int,
        runtimeCheckCount: Int,
        repositoryCount: Int,
        plannedParallelism: Int,
        category: CodexTaskCategory,
        complexity: CodexTaskComplexity,
        classifierVersion: Int = 1
    ) {
        self.stepCount = max(0, stepCount)
        self.workUnitCount = max(0, workUnitCount)
        self.verificationCount = max(0, verificationCount)
        self.buildCount = max(0, buildCount)
        self.runtimeCheckCount = max(0, runtimeCheckCount)
        self.repositoryCount = max(0, repositoryCount)
        self.plannedParallelism = max(0, plannedParallelism)
        self.category = category
        self.complexity = complexity
        self.classifierVersion = classifierVersion
    }

    public var summary: String {
        let complexityText = complexity.rawValue.replacingOccurrences(of: "_", with: " ")
        return "\(complexityText) \(stepCount)-step plan"
    }
}

public struct CodexTaskPlanSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let taskID: String
    public let observedAt: Date
    public let features: CodexTaskPlanFeatures

    public var id: String { taskID }

    public init(taskID: String, observedAt: Date, features: CodexTaskPlanFeatures) {
        self.taskID = taskID
        self.observedAt = observedAt
        self.features = features
    }
}

public enum CodexTaskForecastModel: String, Codable, Sendable {
    case empirical
    case logNormal = "log_normal"
    case normalDiagnostic = "normal_diagnostic"
    case baseline
}

public struct CodexPlanAwareTaskEstimate: Equatable, Sendable {
    public let typicalTotal: TimeInterval?
    public let planUpperTotal: TimeInterval?
    public let safeAwayRemaining: TimeInterval?
    public let model: CodexTaskForecastModel
    public let confidence: CodexTaskDurationConfidence
    public let sampleCount: Int
    public let scope: CodexTaskDurationEstimateScope
    public let planSummary: String?

    public init(
        typicalTotal: TimeInterval?,
        planUpperTotal: TimeInterval?,
        safeAwayRemaining: TimeInterval?,
        model: CodexTaskForecastModel,
        confidence: CodexTaskDurationConfidence,
        sampleCount: Int,
        scope: CodexTaskDurationEstimateScope,
        planSummary: String?
    ) {
        self.typicalTotal = typicalTotal
        self.planUpperTotal = planUpperTotal
        self.safeAwayRemaining = safeAwayRemaining
        self.model = model
        self.confidence = confidence
        self.sampleCount = max(0, sampleCount)
        self.scope = scope
        self.planSummary = planSummary
    }
}

public enum CodexGoalStatus: String, Codable, Sendable {
    case active
    case paused
    case complete
    case blocked

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CodexGoalStatus(rawValue: value) ?? .paused
    }
}

public struct CodexGoalActivity: Equatable, Identifiable, Sendable {
    public let threadID: String
    public let createdAt: Date
    public var updatedAt: Date
    public var status: CodexGoalStatus
    public var activeDuration: TimeInterval
    public var workingDirectory: String?

    public var id: String {
        "\(threadID):\(createdAt.timeIntervalSince1970)"
    }

    public var wallDuration: TimeInterval {
        max(0, updatedAt.timeIntervalSince(createdAt))
    }

    public var isActive: Bool { status == .active }
    public var isTerminal: Bool { status == .complete || status == .blocked }

    public init(
        threadID: String,
        createdAt: Date,
        updatedAt: Date,
        status: CodexGoalStatus,
        activeDuration: TimeInterval,
        workingDirectory: String? = nil
    ) {
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.activeDuration = max(0, activeDuration)
        self.workingDirectory = workingDirectory
    }
}

public struct CodexSwarmActivity: Equatable, Identifiable, Sendable {
    public let parentTaskID: String
    public let sessionID: String
    public let turnID: String
    public var firstSpawnedAt: Date
    public var agentCount: Int
    public var completedAt: Date?
    public var workingDirectory: String?

    public var id: String { parentTaskID }
    public var isActive: Bool { completedAt == nil }

    public init(
        parentTaskID: String,
        sessionID: String,
        turnID: String,
        firstSpawnedAt: Date,
        agentCount: Int = 1,
        completedAt: Date? = nil,
        workingDirectory: String? = nil
    ) {
        self.parentTaskID = parentTaskID
        self.sessionID = sessionID
        self.turnID = turnID
        self.firstSpawnedAt = firstSpawnedAt
        self.agentCount = max(1, agentCount)
        self.completedAt = completedAt
        self.workingDirectory = workingDirectory
    }

    public var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(firstSpawnedAt))
    }
}

public enum CodexForecastEntityType: String, Codable, Sendable {
    case task
    case goal
    case swarm
}

public struct CodexForecastObservation: Equatable, Identifiable, Sendable {
    public let id: String
    public let entityType: CodexForecastEntityType
    public let entityID: String
    public let observedAt: Date
    public let elapsedDuration: TimeInterval
    public let medianRemaining: TimeInterval?
    public let safeRemaining: TimeInterval?
    public let probabilityWithinHorizon: Double?
    public let horizon: TimeInterval?
    public let sampleCount: Int
    public let scope: CodexTaskDurationEstimateScope
    public let typicalTotal: TimeInterval?
    public let upperTotal: TimeInterval?
    public let safeAwayRemaining: TimeInterval?
    public let model: CodexTaskForecastModel
    public let actualDuration: TimeInterval?
    public let actualStatus: String?

    public init(
        id: String,
        entityType: CodexForecastEntityType,
        entityID: String,
        observedAt: Date,
        elapsedDuration: TimeInterval,
        medianRemaining: TimeInterval?,
        safeRemaining: TimeInterval?,
        probabilityWithinHorizon: Double?,
        horizon: TimeInterval?,
        sampleCount: Int,
        scope: CodexTaskDurationEstimateScope,
        typicalTotal: TimeInterval? = nil,
        upperTotal: TimeInterval? = nil,
        safeAwayRemaining: TimeInterval? = nil,
        model: CodexTaskForecastModel = .baseline,
        actualDuration: TimeInterval? = nil,
        actualStatus: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.observedAt = observedAt
        self.elapsedDuration = max(0, elapsedDuration)
        self.medianRemaining = medianRemaining
        self.safeRemaining = safeRemaining
        self.probabilityWithinHorizon = probabilityWithinHorizon
        self.horizon = horizon
        self.sampleCount = max(0, sampleCount)
        self.scope = scope
        self.typicalTotal = typicalTotal
        self.upperTotal = upperTotal
        self.safeAwayRemaining = safeAwayRemaining
        self.model = model
        self.actualDuration = actualDuration
        self.actualStatus = actualStatus
    }
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

    public var projectDisplayName: String {
        guard let workingDirectory else { return "Codex task" }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Codex task" : name
    }

    public var isRunning: Bool {
        status == .working || (status == .queued && startedAt != nil)
    }

    public var visibleStatus: CodexTaskStatus {
        isRunning ? .working : status
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
