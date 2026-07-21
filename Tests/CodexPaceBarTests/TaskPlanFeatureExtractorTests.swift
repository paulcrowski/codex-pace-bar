import CodexPaceBarCore
import Testing

struct TaskPlanFeatureExtractorTests {
    @Test
    func countsVerificationAndParallelWorkWithoutReturningText() throws {
        let object: [String: Any] = [
            "plan": [
                ["step": "Implement feature and test", "status": "in_progress"],
                ["step": "Build, smoke check, and verify", "status": "pending"]
            ]
        ]
        let features = try #require(CodexTaskPlanFeatureExtractor().features(from: object))
        #expect(features.stepCount == 2)
        #expect(features.workUnitCount >= 3)
        #expect(features.verificationCount >= 2)
        #expect(features.buildCount == 1)
        #expect(features.category == .feature)
        #expect(features.complexity == .complex)
        #expect(features.summary.contains("2-step"))
    }
}
