import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct RateLimitWindowSelectorTests {
    @Test
    func choosesExactCodexWeeklySecondaryWindow() throws {
        let result = try json("""
        {
          "rateLimits": {
            "limitId": "codex",
            "primary": {"usedPercent": 10, "windowDurationMins": 300, "resetsAt": 2000},
            "secondary": {"usedPercent": 90, "windowDurationMins": 10080, "resetsAt": 3000}
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "primary": {"usedPercent": 11, "windowDurationMins": 300, "resetsAt": 2000},
              "secondary": {"usedPercent": 76, "windowDurationMins": 10080, "resetsAt": 4000}
            }
          }
        }
        """)

        let selection = try RateLimitWindowSelector.select(from: result)

        #expect(selection.window.source == "rateLimitsByLimitId.codex.secondary")
        #expect(selection.window.usedPercent == 76)
        #expect(selection.window.resetsAt.timeIntervalSince1970 == 4000)
    }

    @Test
    func fallsBackToTopLevelRateLimits() throws {
        let result = try json("""
        {
          "rateLimits": {
            "limitId": "codex",
            "secondary": {"usedPercent": 33, "windowDurationMins": 10080, "resetsAt": 5000}
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "primary": {"usedPercent": 1, "windowDurationMins": 300, "resetsAt": 2000}
            }
          }
        }
        """)

        let selection = try RateLimitWindowSelector.select(from: result)

        #expect(selection.window.source == "rateLimits.secondary")
        #expect(selection.window.usedPercent == 33)
    }

    @Test
    func fallsBackToCodexPrefixedLimitIdAfterExactCodexAndTopLevelFail() throws {
        let result = try json("""
        {
          "rateLimits": {
            "limitId": "codex",
            "primary": {"usedPercent": 2, "windowDurationMins": 300, "resetsAt": 2000}
          },
          "rateLimitsByLimitId": {
            "other": {
              "limitId": "other",
              "secondary": {"usedPercent": 99, "windowDurationMins": 10080, "resetsAt": 5000}
            },
            "codex_bengalfox": {
              "limitId": "codex_bengalfox",
              "secondary": {"usedPercent": 4, "windowDurationMins": 10080, "resetsAt": 6000}
            }
          }
        }
        """)

        let selection = try RateLimitWindowSelector.select(from: result)

        #expect(selection.window.source == "rateLimitsByLimitId.codex_bengalfox.secondary")
        #expect(selection.window.limitId == "codex_bengalfox")
        #expect(selection.window.usedPercent == 4)
    }

    @Test
    func returnsErrorWhenWeeklyWindowHasNoResetTimestamp() throws {
        let result = try json("""
        {
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "secondary": {"usedPercent": 44, "windowDurationMins": 10080}
            }
          }
        }
        """)

        try expectPaceError(.noWeeklyWindowFound) {
            _ = try RateLimitWindowSelector.select(from: result)
        }
    }

    @Test
    func returnsErrorWhenWindowDurationIsMissing() throws {
        let result = try json("""
        {
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "secondary": {"usedPercent": 44, "resetsAt": 6000}
            }
          }
        }
        """)

        try expectPaceError(.noWeeklyWindowFound) {
            _ = try RateLimitWindowSelector.select(from: result)
        }
    }

    private func json(_ string: String) throws -> JSONValue {
        try JSONValue.parse(data: Data(string.utf8))
    }

    private func expectPaceError(_ expected: PaceError, operation: () throws -> Void) throws {
        do {
            try operation()
            Issue.record("Expected \(expected)")
        } catch let error as PaceError {
            #expect(error == expected)
        }
    }
}
