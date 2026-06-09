import Foundation

public enum RateLimitWindowSelector {
    private static let weeklyDurationMins = 10080.0

    public static func select(from result: JSONValue) throws -> RateLimitSelection {
        guard let root = result.objectValue else {
            throw PaceError.invalidRateLimitSchema("Root result was not an object.")
        }

        var candidates: [RateLimitCandidate] = []

        if let exactCodex = root["rateLimitsByLimitId"]?["codex"] {
            if let selected = selectedWindow(from: exactCodex, source: "rateLimitsByLimitId.codex", candidates: &candidates) {
                return RateLimitSelection(window: selected, candidates: candidates)
            }
        }

        if let fallback = root["rateLimits"] {
            if let selected = selectedWindow(from: fallback, source: "rateLimits", candidates: &candidates) {
                return RateLimitSelection(window: selected, candidates: candidates)
            }
        }

        if let byLimitId = root["rateLimitsByLimitId"]?.objectValue {
            for key in byLimitId.keys.sorted() where key != "codex" {
                guard let snapshot = byLimitId[key] else {
                    continue
                }
                let snapshotLimitId = snapshot["limitId"]?.stringValue
                guard key.hasPrefix("codex") || snapshotLimitId?.hasPrefix("codex") == true else {
                    continue
                }

                if let selected = selectedWindow(from: snapshot, source: "rateLimitsByLimitId.\(key)", candidates: &candidates) {
                    return RateLimitSelection(window: selected, candidates: candidates)
                }
            }
        }

        throw PaceError.noWeeklyWindowFound
    }

    private static func selectedWindow(
        from snapshot: JSONValue,
        source: String,
        candidates: inout [RateLimitCandidate]
    ) -> CodexLimitWindow? {
        guard let object = snapshot.objectValue else {
            return nil
        }

        let limitId = object["limitId"]?.stringValue ?? source
        for kind in ["primary", "secondary"] {
            guard let windowValue = object[kind], windowValue != .null else {
                continue
            }

            let candidate = candidate(from: windowValue, source: source, limitId: object["limitId"]?.stringValue, kind: kind)
            candidates.append(candidate)

            guard candidate.windowDurationMins == weeklyDurationMins,
                  let usedPercent = candidate.usedPercent,
                  let resetsAtSeconds = windowValue["resetsAt"]?.doubleValue,
                  resetsAtSeconds.isFinite,
                  resetsAtSeconds > 0
            else {
                continue
            }

            return CodexLimitWindow(
                limitId: limitId,
                source: "\(source).\(kind)",
                usedPercent: usedPercent,
                windowDurationMins: weeklyDurationMins,
                resetsAt: Date(timeIntervalSince1970: resetsAtSeconds)
            )
        }

        return nil
    }

    private static func candidate(from windowValue: JSONValue, source: String, limitId: String?, kind: String) -> RateLimitCandidate {
        RateLimitCandidate(
            source: source,
            limitId: limitId,
            kind: kind,
            usedPercent: windowValue["usedPercent"]?.doubleValue,
            windowDurationMins: windowValue["windowDurationMins"]?.doubleValue,
            hasResetsAt: windowValue["resetsAt"]?.doubleValue != nil
        )
    }
}
