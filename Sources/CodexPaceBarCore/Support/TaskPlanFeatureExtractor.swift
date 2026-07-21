import Foundation

/// Converts a plan into bounded numeric metadata. Raw step text is never returned.
public struct CodexTaskPlanFeatureExtractor: Sendable {
    public init() {}

    public func features(from planObject: Any) -> CodexTaskPlanFeatures? {
        let steps: [[String: Any]]
        if let object = planObject as? [String: Any],
           let rawSteps = object["plan"] as? [[String: Any]] {
            steps = rawSteps
        } else if let rawSteps = planObject as? [[String: Any]] {
            steps = rawSteps
        } else {
            return nil
        }
        guard !steps.isEmpty else { return nil }

        let texts = steps.map { step in
            ["step", "description", "title", "content", "summary"]
                .compactMap { step[$0] as? String }
                .joined(separator: " ")
                .lowercased()
        }
        let joined = texts.joined(separator: " ")
        let stepCount = steps.count
        let conjunctions = texts.reduce(0) { partial, text in
            partial + countMatches(in: text, terms: [" and ", " oraz ", " i ", ",", ";", " + "])
        }
        let workUnitCount = max(stepCount, stepCount + conjunctions)
        let verificationCount = countMatches(
            in: joined,
            terms: ["test", "verify", "verification", "smoke", "audit", "check", "proof", "weryfik", "testy"]
        )
        let buildCount = countMatches(in: joined, terms: ["build", "compile", "release", "swift build", "kompil"])
        let runtimeCheckCount = countMatches(in: joined, terms: ["runtime", "launch", "run", "uruchom", "manual ui", "visual"])
        let repositoryCount = max(1, countMatches(in: joined, terms: ["repo", "repository", "repozytor", "workspace"]))
        let plannedParallelism = countMatches(in: joined, terms: ["agent", "swarm", "parallel", "równoleg", "delegat"])
        let category = category(for: joined)
        let score = workUnitCount
            + verificationCount
            + buildCount
            + runtimeCheckCount
            + plannedParallelism
        let complexity: CodexTaskComplexity
        if score >= 18 || stepCount >= 8 {
            complexity = .veryComplex
        } else if score >= 10 || stepCount >= 4 {
            complexity = .complex
        } else if score >= 5 || stepCount >= 2 {
            complexity = .medium
        } else {
            complexity = .simple
        }

        return CodexTaskPlanFeatures(
            stepCount: stepCount,
            workUnitCount: workUnitCount,
            verificationCount: verificationCount,
            buildCount: buildCount,
            runtimeCheckCount: runtimeCheckCount,
            repositoryCount: repositoryCount,
            plannedParallelism: plannedParallelism,
            category: category,
            complexity: complexity
        )
    }

    private func category(for text: String) -> CodexTaskCategory {
        if containsAny(text, ["audit", "review", "inspect", "quality", "audyt", "przegląd"]) { return .audit }
        if containsAny(text, ["research", "investigate", "research", "zbada", "sprawdź dane"]) { return .research }
        if containsAny(text, ["data", "database", "csv", "histogram", "distribution", "dane", "baza"]) { return .dataAnalysis }
        if containsAny(text, ["release", "publish", "deploy", "push", "commit", "wydaj", "publik"]) { return .release }
        if containsAny(text, ["feature", "implement", "add ", "dodaj", "wdroż", "zbuduj"]) { return .feature }
        if containsAny(text, ["fix", "repair", "bug", "napraw", "popraw"]) { return .smallFix }
        if text.split(separator: " ").count <= 18 { return .question }
        return .unknown
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func countMatches(in text: String, terms: [String]) -> Int {
        terms.reduce(0) { $0 + (text.components(separatedBy: $1).count - 1) }
    }
}
