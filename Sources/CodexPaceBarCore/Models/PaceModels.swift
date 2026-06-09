import Foundation

public enum PaceState: Equatable, Sendable {
    case belowPace
    case onPace
    case abovePace
    case loading
    case error

    public var statusTitle: String {
        switch self {
        case .belowPace:
            return "Below pace"
        case .onPace:
            return "On pace"
        case .abovePace:
            return "Above pace"
        case .loading:
            return "Loading"
        case .error:
            return "Error"
        }
    }

    public var isValidPaceState: Bool {
        switch self {
        case .belowPace, .onPace, .abovePace:
            return true
        case .loading, .error:
            return false
        }
    }
}

public enum BarColorScheme: String, CaseIterable, Identifiable, Sendable {
    case statusColor
    case paceComparison

    public var id: String { rawValue }

    public var settingsTitle: String {
        switch self {
        case .statusColor:
            return "Status color"
        case .paceComparison:
            return "Pace comparison"
        }
    }
}

public struct CodexLimitWindow: Equatable, Sendable {
    public let limitId: String
    public let source: String
    public let usedPercent: Double
    public let windowDurationMins: Double
    public let resetsAt: Date

    public init(limitId: String, source: String, usedPercent: Double, windowDurationMins: Double, resetsAt: Date) {
        self.limitId = limitId
        self.source = source
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct PaceSnapshot: Equatable, Sendable {
    public let actualUsedPercent: Double
    public let remainingPercent: Double
    public let idealUsedPercent: Double
    public let deltaPercentagePoints: Double
    public let usedFraction: Double
    public let elapsedFraction: Double
    public let resetAt: Date
    public let state: PaceState
    public let fetchedAt: Date
    public let isStale: Bool

    public init(
        actualUsedPercent: Double,
        remainingPercent: Double,
        idealUsedPercent: Double,
        deltaPercentagePoints: Double,
        usedFraction: Double,
        elapsedFraction: Double,
        resetAt: Date,
        state: PaceState,
        fetchedAt: Date,
        isStale: Bool
    ) {
        self.actualUsedPercent = actualUsedPercent
        self.remainingPercent = remainingPercent
        self.idealUsedPercent = idealUsedPercent
        self.deltaPercentagePoints = deltaPercentagePoints
        self.usedFraction = usedFraction
        self.elapsedFraction = elapsedFraction
        self.resetAt = resetAt
        self.state = state
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }
}

public struct RateLimitCandidate: Equatable, Sendable {
    public let source: String
    public let limitId: String?
    public let kind: String
    public let usedPercent: Double?
    public let windowDurationMins: Double?
    public let hasResetsAt: Bool

    public init(
        source: String,
        limitId: String?,
        kind: String,
        usedPercent: Double?,
        windowDurationMins: Double?,
        hasResetsAt: Bool
    ) {
        self.source = source
        self.limitId = limitId
        self.kind = kind
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.hasResetsAt = hasResetsAt
    }
}

public struct RateLimitSelection: Equatable, Sendable {
    public let window: CodexLimitWindow
    public let candidates: [RateLimitCandidate]

    public init(window: CodexLimitWindow, candidates: [RateLimitCandidate]) {
        self.window = window
        self.candidates = candidates
    }
}
