import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import SQLite3
import Testing

struct NativeGoalStoreTests {
    @Test
    func readsActiveGoalTimingWithoutLoadingObjectiveText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarNativeGoalTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("goals.sqlite")

        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE thread_goals (
            thread_id TEXT PRIMARY KEY NOT NULL,
            goal_id TEXT NOT NULL,
            objective TEXT NOT NULL,
            status TEXT NOT NULL,
            token_budget INTEGER,
            tokens_used INTEGER NOT NULL DEFAULT 0,
            time_used_seconds INTEGER NOT NULL DEFAULT 0,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
        );
        INSERT INTO thread_goals VALUES (
            'thread-active', 'goal-1', 'private objective', 'active', NULL, 10, 1_772,
            1_784_729_000_000, 1_784_729_120_000
        );
        INSERT INTO thread_goals VALUES (
            'thread-complete', 'goal-2', 'completed objective', 'complete', NULL, 10, 100,
            1_784_729_000_000, 1_784_729_100_000
        );
        """
        #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)

        let goals = try CodexNativeGoalStore(databaseURL: url).activeGoals()
        let goal = try #require(goals.first)
        #expect(goals.count == 1)
        #expect(goal.threadID == "thread-active")
        #expect(goal.status == .active)
        #expect(goal.activeDuration == 1_772)
        #expect(goal.createdAt.timeIntervalSince1970 == 1_784_729_000)
        #expect(goal.updatedAt.timeIntervalSince1970 == 1_784_729_120)
    }
}
