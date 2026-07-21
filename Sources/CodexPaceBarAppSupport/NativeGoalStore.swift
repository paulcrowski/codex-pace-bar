import CodexPaceBarCore
import Foundation
import SQLite3

/// Read-only bridge to Codex Desktop's native goal state.
///
/// The objective column is intentionally never selected. Task Monitor needs
/// only lifecycle/timing metadata to show and estimate the active goal.
public struct CodexNativeGoalStore: Sendable {
    public enum StoreError: Error, Equatable {
        case openFailed(String)
        case queryFailed(String)
    }

    private let databaseURL: URL?

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    public func activeGoals() throws -> [CodexGoalActivity] {
        guard let url = databaseURL ?? Self.defaultDatabaseURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            if let database { sqlite3_close(database) }
            throw StoreError.openFailed(url.path)
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT thread_id, created_at_ms, updated_at_ms, status, time_used_seconds
        FROM thread_goals
        WHERE status = 'active'
        ORDER BY updated_at_ms DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw StoreError.queryFailed(Self.errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var goals: [CodexGoalActivity] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let threadID = Self.stringColumn(statement, index: 0),
                  let createdAtMilliseconds = Self.doubleColumn(statement, index: 1),
                  let updatedAtMilliseconds = Self.doubleColumn(statement, index: 2),
                  let statusRaw = Self.stringColumn(statement, index: 3),
                  let activeDuration = Self.doubleColumn(statement, index: 4),
                  let status = Self.goalStatus(statusRaw),
                  createdAtMilliseconds.isFinite,
                  updatedAtMilliseconds.isFinite,
                  activeDuration.isFinite,
                  updatedAtMilliseconds >= createdAtMilliseconds
            else { continue }
            goals.append(CodexGoalActivity(
                threadID: threadID,
                createdAt: Date(timeIntervalSince1970: createdAtMilliseconds / 1_000),
                updatedAt: Date(timeIntervalSince1970: updatedAtMilliseconds / 1_000),
                status: status,
                activeDuration: activeDuration
            ))
        }
        return goals
    }

    public static var defaultDatabaseURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/goals_1.sqlite"),
            home.appendingPathComponent(".codex/sqlite/goals_1.sqlite")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func goalStatus(_ raw: String) -> CodexGoalStatus? {
        switch raw {
        case "active": .active
        case "paused": .paused
        case "blocked", "usage_limited", "budget_limited": .blocked
        case "complete": .complete
        default: nil
        }
    }

    private static func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func doubleColumn(_ statement: OpaquePointer?, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "unknown SQLite error" }
        return String(cString: message)
    }
}
