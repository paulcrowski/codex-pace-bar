@testable import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import Testing

@MainActor
@Suite
struct MobileTaskNotificationTests {
    @Test
    func androidSubscriptionURLUsesNativeNtfyDeepLink() throws {
        let url = try #require(MobileTaskNotificationService.androidSubscriptionURL(
            topic: "codex-pace-bar-private"
        ))

        #expect(url.scheme == "ntfy")
        #expect(url.host == "ntfy.sh")
        #expect(url.path == "/codex-pace-bar-private")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "display", value: "Codex Pace Bar")
        ])
        #expect(MobileTaskNotificationService.androidSubscriptionURL(topic: "bad/topic") == nil)
    }

    @Test
    func primingSuppressesExistingTasksThenFreshCompletionSendsExactlyOnce() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(defaults: defaults) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let existing = task(id: "existing", status: .completed, eventAt: now)

        service.prime(with: [existing])
        await service.notifyIfNeeded(
            for: [existing],
            enabled: true,
            topic: "codex-pace-bar-private",
            now: now
        )
        #expect(requests.isEmpty)

        let fresh = task(id: "fresh", status: .completed, eventAt: now.addingTimeInterval(5))
        await service.notifyIfNeeded(
            for: [existing, fresh],
            enabled: true,
            topic: "codex-pace-bar-private",
            now: now.addingTimeInterval(5)
        )
        await service.notifyIfNeeded(
            for: [existing, fresh],
            enabled: true,
            topic: "codex-pace-bar-private",
            now: now.addingTimeInterval(6)
        )

        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url?.absoluteString == "https://ntfy.sh/codex-pace-bar-private")
        #expect(requests.first?.value(forHTTPHeaderField: "Title") == "Codex task finished")
        #expect(requests.first?.value(forHTTPHeaderField: "Priority") == "high")
        #expect(String(data: try #require(requests.first?.httpBody), encoding: .utf8) == "A Codex task is ready on your Mac.")
    }

    @Test
    func oldEventsInvalidTopicsAndDisabledDeliveryDoNotSend() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requestCount = 0
        let service = MobileTaskNotificationService(defaults: defaults) { request in
            requestCount += 1
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 2_000_000)
        service.prime(with: [])
        let old = task(id: "old", status: .completed, eventAt: now.addingTimeInterval(-301))
        let fresh = task(id: "fresh", status: .completed, eventAt: now)

        await service.notifyIfNeeded(for: [old], enabled: true, topic: "valid-topic", now: now)
        await service.notifyIfNeeded(for: [fresh], enabled: false, topic: "valid-topic", now: now)
        await service.notifyIfNeeded(for: [fresh], enabled: true, topic: "bad/topic", now: now)
        await service.notifyIfNeeded(for: [fresh], enabled: true, topic: "zażółć", now: now)

        #expect(requestCount == 0)
    }

    @Test
    func deliveredEventPersistsAcrossServiceInstances() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requestCount = 0
        let sender: MobileTaskNotificationService.RequestSender = { request in
            requestCount += 1
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 3_000_000)
        let fresh = task(id: "fresh", status: .needsApproval, eventAt: now)

        let first = MobileTaskNotificationService(defaults: defaults, sender: sender)
        first.prime(with: [])
        await first.notifyIfNeeded(for: [fresh], enabled: true, topic: "private-topic", now: now)

        let second = MobileTaskNotificationService(defaults: defaults, sender: sender)
        second.prime(with: [])
        await second.notifyIfNeeded(for: [fresh], enabled: true, topic: "private-topic", now: now)

        #expect(requestCount == 1)
    }

    @Test
    func failedDeliveryIsRetriedAndTestMessageUsesMinimalPayload() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        var shouldFail = true
        let service = MobileTaskNotificationService(defaults: defaults) { request in
            requests.append(request)
            if shouldFail {
                shouldFail = false
                throw URLError(.notConnectedToInternet)
            }
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 4_000_000)
        let fresh = task(id: "fresh", status: .completed, eventAt: now)
        service.prime(with: [])

        await service.notifyIfNeeded(for: [fresh], enabled: true, topic: "private-topic", now: now)
        await service.notifyIfNeeded(for: [fresh], enabled: true, topic: "private-topic", now: now)
        let testSent = await service.sendTest(topic: "private-topic")

        #expect(requests.count == 3)
        #expect(testSent)
        #expect(requests.last?.value(forHTTPHeaderField: "Title") == "Codex Pace Bar test")
        #expect(requests.last?.value(forHTTPHeaderField: "Priority") == "high")
        #expect(String(data: try #require(requests.last?.httpBody), encoding: .utf8) == "Phone notifications are connected.")
    }

    @Test
    func optedInDetailsIncludeOnlyProjectNameAndDuration() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(defaults: defaults) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 5_000_000)
        let completed = task(id: "detailed", status: .completed, eventAt: now)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [completed],
            enabled: true,
            topic: "private-topic",
            includeDetails: true,
            now: now
        )

        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Title") == "Codex task finished")
        #expect(String(data: try #require(requests.first?.httpBody), encoding: .utf8) == "Task in project-name-must-not-leak completed in 1 min.")
    }

    @Test
    func silentModeBatchesSeveralCompletionsIntoOneAlert() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(
            defaults: defaults,
            quietInterval: 0.02
        ) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 6_000_000)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [
                task(id: "first", status: .completed, eventAt: now),
                task(id: "second", status: .completed, eventAt: now)
            ],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now
        )

        #expect(requests.isEmpty)
        try await Task.sleep(for: .milliseconds(60))
        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Title") == "Codex work ready")
        #expect(String(data: try #require(requests.first?.httpBody), encoding: .utf8) == "2 Codex tasks completed.")
    }

    @Test
    func silentModeCancelsFinishAlertWhileNewWorkIsRunning() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(
            defaults: defaults,
            quietInterval: 0.03
        ) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 7_000_000)
        let first = task(id: "first", status: .completed, eventAt: now)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [first],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now
        )
        await service.notifyIfNeeded(
            for: [first, task(id: "next", status: .working, eventAt: now.addingTimeInterval(1))],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now.addingTimeInterval(1)
        )

        try await Task.sleep(for: .milliseconds(70))
        #expect(requests.isEmpty)

        await service.notifyIfNeeded(
            for: [first, task(id: "next", status: .completed, eventAt: now.addingTimeInterval(2))],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now.addingTimeInterval(2)
        )
        try await Task.sleep(for: .milliseconds(70))
        #expect(requests.count == 1)
    }

    @Test
    func silentModeStillSendsNeedsYouImmediately() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(
            defaults: defaults,
            quietInterval: 60
        ) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 8_000_000)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [task(id: "approval", status: .needsApproval, eventAt: now)],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now
        )

        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Title") == "Codex needs you")
    }

    @Test
    func nativeGoalStaysSilentAcrossTurnsAndSendsOneGoalAlert() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requests: [URLRequest] = []
        let service = MobileTaskNotificationService(
            defaults: defaults,
            quietInterval: 0.02
        ) { request in
            requests.append(request)
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 10_000_000)
        let activeGoal = goal(status: .active, updatedAt: now)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [task(id: "turn", status: .completed, eventAt: now)],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            goals: [activeGoal],
            now: now
        )
        try await Task.sleep(for: .milliseconds(60))
        #expect(requests.isEmpty)

        let completedGoal = goal(status: .complete, updatedAt: now.addingTimeInterval(1))
        await service.notifyIfNeeded(
            for: [task(id: "turn", status: .completed, eventAt: now.addingTimeInterval(1))],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            goals: [completedGoal],
            now: now.addingTimeInterval(1)
        )

        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Title") == "Codex goal finished")
    }

    @Test
    func failedSilentBatchStaysPendingAndRetries() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        var requestCount = 0
        let service = MobileTaskNotificationService(
            defaults: defaults,
            quietInterval: 0.01
        ) { request in
            requestCount += 1
            if requestCount == 1 {
                throw URLError(.notConnectedToInternet)
            }
            return try successResponse(for: request)
        }
        let now = Date(timeIntervalSince1970: 9_000_000)
        service.prime(with: [])

        await service.notifyIfNeeded(
            for: [task(id: "retry", status: .completed, eventAt: now)],
            enabled: true,
            topic: "private-topic",
            silentGoalsAndSwarmsEnabled: true,
            now: now
        )

        try await Task.sleep(for: .milliseconds(300))
        #expect(requestCount == 2)
    }

    private let defaultsSuiteName = "CodexPaceBarMobileNotificationTests-" + UUID().uuidString

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName)!
    }

    private func task(id: String, status: CodexTaskStatus, eventAt: Date) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: "session-\(id)",
            turnID: "turn-\(id)",
            workingDirectory: "/private/project-name-must-not-leak",
            model: "model",
            effort: "high",
            status: status,
            startedAt: eventAt.addingTimeInterval(-60),
            completedAt: status == .completed ? eventAt : nil,
            duration: status == .completed ? 60 : nil,
            timeToFirstToken: nil,
            lastEventAt: eventAt
        )
    }

    private func goal(status: CodexGoalStatus, updatedAt: Date) -> CodexGoalActivity {
        CodexGoalActivity(
            threadID: "session-turn",
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            status: status,
            activeDuration: 60,
            workingDirectory: "/private/project-name-must-not-leak"
        )
    }

    private func successResponse(for request: URLRequest) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        return (Data(), response)
    }
}
