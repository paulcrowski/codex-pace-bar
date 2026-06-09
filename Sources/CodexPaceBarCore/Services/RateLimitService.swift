import Foundation

public struct RateLimitFetchResult: Sendable {
    public let selection: RateLimitSelection
    public let debugInfo: RedactedDebugInfo

    public init(selection: RateLimitSelection, debugInfo: RedactedDebugInfo) {
        self.selection = selection
        self.debugInfo = debugInfo
    }
}

public actor RateLimitService {
    private let executableURL: URL
    private let client: CodexAppServerClient

    public init(executableURL: URL) {
        self.executableURL = executableURL
        self.client = CodexAppServerClient(executableURL: executableURL)
    }

    public func fetchWeeklyLimit() async throws -> RateLimitFetchResult {
        do {
            try await client.ensureInitialized()
            _ = try await client.request(
                method: "account/read",
                params: .object(["refreshToken": .bool(false)]),
                timeoutSeconds: 10
            )

            let rateLimits = try await client.request(
                method: "account/rateLimits/read",
                timeoutSeconds: 10
            )
            let selection = try RateLimitWindowSelector.select(from: rateLimits)
            let debugInfo = RedactedDebugInfo(
                executablePath: executableURL.path,
                appServerStatus: "running",
                lastMethod: "account/rateLimits/read",
                selectedSource: selection.window.source,
                candidates: selection.candidates,
                generatedAt: Date()
            )
            return RateLimitFetchResult(selection: selection, debugInfo: debugInfo)
        } catch let error as PaceError {
            throw error
        } catch {
            throw PaceError.accountReadFailed(error.localizedDescription)
        }
    }

    public func shutdown() async {
        await client.shutdown()
    }
}
