import CodexPaceBarCore
import Foundation
import Testing

struct TaskDurationDistributionAnalyzerTests {
    @Test
    func reportsWalkForwardCalibrationFromPersistedOutcomes() {
        let analyzer = CodexTaskDurationDistributionAnalyzer(minimumSamples: 1)
        let now = Date(timeIntervalSince1970: 1_784_373_000)
        let observations = [
            CodexForecastObservation(
                id: "task:1:0",
                entityType: .task,
                entityID: "task-1",
                observedAt: now,
                elapsedDuration: 120,
                medianRemaining: 180,
                safeRemaining: 300,
                probabilityWithinHorizon: 0.8,
                horizon: 300,
                sampleCount: 20,
                scope: .project,
                typicalTotal: 300,
                upperTotal: 500,
                safeAwayRemaining: 60,
                model: .empirical,
                actualDuration: 420,
                actualStatus: CodexTaskStatus.completed.rawValue
            ),
            CodexForecastObservation(
                id: "goal:1:0",
                entityType: .goal,
                entityID: "goal-1",
                observedAt: now,
                elapsedDuration: 0,
                medianRemaining: 100,
                safeRemaining: 200,
                probabilityWithinHorizon: 0.5,
                horizon: 100,
                sampleCount: 20,
                scope: .global,
                actualDuration: 120,
                actualStatus: CodexGoalStatus.complete.rawValue
            )
        ]

        let report = analyzer.calibrationReport(for: observations)

        #expect(report.sampleCount == 1)
        #expect(report.medianAbsoluteError == 120)
        #expect(report.p85Coverage == 1)
        #expect(report.safeAwayCoverage == 0)
        #expect(abs((report.probabilityBrierScore ?? 1) - 0.04) < 0.000_001)
    }

    @Test
    func rejectsInvalidAndVeryShortDurations() {
        let stats = CodexTaskDurationDistributionAnalyzer(minimumSamples: 2).stats(for: [0, 1, 2, 3, 4, .infinity])
        #expect(stats?.sampleCount == 2)
        #expect(stats?.median == 3.5)
    }

    @Test
    func identifiesRightSkewAndUsesPositiveLogNormalQuantiles() throws {
        let values = (1...30).map { TimeInterval($0 * 60) } + [3_600, 5_400]
        let model = try #require(CodexTaskDurationDistributionAnalyzer().model(for: values))
        #expect(model.kind == .logNormal)
        #expect(model.quantile(0.2) > 0)
        #expect(model.quantile(0.5) <= model.quantile(0.85))
        #expect(model.conditionalCompletionProbability(elapsed: 600, horizon: 1_800) >= 0)
        #expect(model.conditionalCompletionProbability(elapsed: 600, horizon: 1_800) <= 1)
    }

    @Test
    func sparseOrSymmetricCohortsStayEmpirical() throws {
        let model = try #require(CodexTaskDurationDistributionAnalyzer().model(for: (1...12).map { TimeInterval($0 * 60) }))
        #expect(model.kind == .empirical)
    }
}
