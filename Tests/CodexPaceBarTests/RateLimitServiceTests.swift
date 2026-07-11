import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct RateLimitServiceTests {
    @Test
    func fetchesAndSelectsWeeklyLimitThroughClientBoundary() async throws {
        let rateLimits = try JSONValue.parse(line: """
        {
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "secondary": {
                "usedPercent": 42,
                "windowDurationMins": 10080,
                "resetsAt": 2000000000
              }
            }
          }
        }
        """)
        let client = StubAppServerClient(rateLimits: rateLimits)
        let executableURL = URL(fileURLWithPath: "/test/codex")
        let service = RateLimitService(executableURL: executableURL, client: client)

        let result = try await service.fetchWeeklyLimit()

        #expect(result.selection.window.usedPercent == 42)
        #expect(result.selection.window.source == "rateLimitsByLimitId.codex.secondary")
        #expect(result.debugInfo.executablePath == executableURL.path)
        #expect(await client.requestedMethods() == ["account/read", "account/rateLimits/read"])
    }
}

private actor StubAppServerClient: CodexAppServerRequesting {
    private let rateLimits: JSONValue
    private var methods: [String] = []

    init(rateLimits: JSONValue) {
        self.rateLimits = rateLimits
    }

    func ensureInitialized() async throws {}

    func request(method: String, params: JSONValue?, timeoutSeconds: TimeInterval) async throws -> JSONValue {
        methods.append(method)
        return method == "account/rateLimits/read" ? rateLimits : .object([:])
    }

    func shutdown() async {}

    func requestedMethods() -> [String] {
        methods
    }
}
