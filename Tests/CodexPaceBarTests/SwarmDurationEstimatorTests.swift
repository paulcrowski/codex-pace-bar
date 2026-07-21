import CodexPaceBarCore
import Foundation
import Testing

struct SwarmDurationEstimatorTests {
    @Test
    func estimatesRemainingWallTimeForSwarmParent() {
        let now = Date(timeIntervalSince1970: 10_100)
        let current = swarm(id: "current", start: 10_000, end: nil)
        let history = [
            swarm(id: "one", start: 8_000, end: 8_200),
            swarm(id: "two", start: 7_000, end: 7_300),
            swarm(id: "three", start: 6_000, end: 6_400)
        ]

        let estimate = CodexSwarmDurationEstimator(minimumSamples: 3).estimate(
            for: current,
            now: now,
            history: history
        )

        #expect(estimate?.confidence == .learned)
        #expect(estimate?.medianRemaining == 200)
        #expect(estimate?.safeRemaining == 300)
    }

    private func swarm(id: String, start: TimeInterval, end: TimeInterval?) -> CodexSwarmActivity {
        CodexSwarmActivity(
            parentTaskID: id,
            sessionID: id,
            turnID: "turn-\(id)",
            firstSpawnedAt: Date(timeIntervalSince1970: start),
            agentCount: 2,
            completedAt: end.map(Date.init(timeIntervalSince1970:)),
            workingDirectory: "/work/project"
        )
    }
}
