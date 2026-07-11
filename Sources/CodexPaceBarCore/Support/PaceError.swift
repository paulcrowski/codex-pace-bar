import Foundation

public enum PaceError: Error, Equatable, LocalizedError, Sendable {
    case codexExecutableNotFound
    case appServerStartupFailed(String)
    case appServerExited(Int32?)
    case appServerTimeout(String)
    case appServerWriteFailed
    case jsonEncodingFailed
    case jsonDecodingFailed(String)
    case jsonRpcError(code: Int?, message: String)
    case accountReadFailed(String)
    case noWeeklyWindowFound
    case invalidRateLimitSchema(String)
    case staleAfterReset(String)

    public var requiresCodexSetup: Bool {
        switch self {
        case .codexExecutableNotFound, .appServerExited(127):
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "Codex executable not found."
        case let .appServerStartupFailed(reason):
            return "App-server failed to start. \(reason)"
        case let .appServerExited(status):
            if let status {
                return "App-server exited with status \(status)."
            }
            return "App-server exited."
        case let .appServerTimeout(operation):
            return "Timed out while waiting for \(operation)."
        case .appServerWriteFailed:
            return "Could not write to app-server."
        case .jsonEncodingFailed:
            return "Could not encode JSON-RPC message."
        case let .jsonDecodingFailed(reason):
            return "Could not decode app-server JSON. \(reason)"
        case let .jsonRpcError(code, message):
            if let code {
                return "App-server returned JSON-RPC error \(code): \(message)"
            }
            return "App-server returned JSON-RPC error: \(message)"
        case let .accountReadFailed(reason):
            return "Could not read Codex account. \(reason)"
        case .noWeeklyWindowFound:
            return "No valid weekly Codex rate-limit window was found."
        case let .invalidRateLimitSchema(reason):
            return "Unexpected rate-limit schema. \(reason)"
        case let .staleAfterReset(reason):
            return "Weekly limit may have reset, but refresh failed. \(reason)"
        }
    }
}
