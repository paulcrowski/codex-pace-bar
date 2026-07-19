import Foundation

public enum CodexTaskMonitorHealth: Equatable, Sendable {
    case loading
    case ready
    case stale(message: String)

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    public var title: String? {
        guard case .stale = self else { return nil }
        return "Task monitor is stale"
    }

    public var detail: String? {
        guard case let .stale(message) = self else { return nil }
        return message
    }
}

public struct CodexTaskMonitorHealthTracker: Equatable, Sendable {
    public private(set) var state: CodexTaskMonitorHealth

    public init(state: CodexTaskMonitorHealth = .loading) {
        self.state = state
    }

    public mutating func markReady() {
        state = .ready
    }

    public mutating func markStale(message: String) {
        state = .stale(message: message)
    }
}
