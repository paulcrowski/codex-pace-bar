import CodexPaceBarCore
import Foundation
import SQLite3

public actor TaskActivityStore {
    private static let schema = """
    CREATE TABLE IF NOT EXISTS task_activity (
        task_key TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        turn_id TEXT NOT NULL,
        working_directory TEXT,
        model TEXT,
        effort TEXT,
        status TEXT NOT NULL,
        started_at REAL,
        completed_at REAL,
        duration REAL,
        time_to_first_token REAL,
        last_event_at REAL,
        waiting_started_at REAL,
        waiting_duration REAL NOT NULL DEFAULT 0,
        transcript_path TEXT,
        terminal_program TEXT,
        terminal_session_id TEXT,
        source_bundle_identifier TEXT
    );
    CREATE TABLE IF NOT EXISTS task_status_event (
        task_key TEXT NOT NULL,
        session_id TEXT NOT NULL,
        turn_id TEXT NOT NULL,
        status TEXT NOT NULL,
        occurred_at REAL NOT NULL,
        UNIQUE(task_key, status, occurred_at)
    );
    CREATE TABLE IF NOT EXISTS daily_work_checkin (
        day_start REAL PRIMARY KEY,
        rating TEXT NOT NULL,
        rhythm_score INTEGER
    );
    """

    private let database: SQLiteConnection
    private var sessionID = "unknown"
    private var sessionWorkingDirectory: String?
    private var contexts: [String: TurnContext] = [:]
    private var currentTurnID: String?
    private var activities: [String: CodexTaskActivity]

    public init(
        databaseURL: URL,
        initialSessionID: String = "unknown",
        loadExisting: Bool = true
    ) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            throw TaskActivityStoreError.openFailed(Self.errorMessage(database))
        }

        do {
            try Self.execute(Self.schema, on: database)
            try Self.migrateLegacySchema(on: database)
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS task_status_event_time ON task_status_event(occurred_at);
                CREATE INDEX IF NOT EXISTS task_activity_last_event ON task_activity(last_event_at);
                CREATE INDEX IF NOT EXISTS task_activity_status_time ON task_activity(status, last_event_at);
                """,
                on: database
            )
            try Self.execute("PRAGMA journal_mode=WAL;", on: database)
            try Self.execute("PRAGMA synchronous=NORMAL;", on: database)
            try Self.execute("PRAGMA busy_timeout=1000;", on: database)
            try Self.execute("PRAGMA cache_size=-2048;", on: database)
            try Self.execute("PRAGMA wal_autocheckpoint=1000;", on: database)
            try Self.secureDatabaseFiles(at: databaseURL)
            self.database = SQLiteConnection(pointer: database)
            if loadExisting {
                let loaded = try Self.loadActivities(from: database)
                let result = Self.deduplicated(loaded)
                try Self.migrateStatusEvents(result.statusEventMigrations, in: database)
                self.activities = result.activities
            } else {
                self.activities = [:]
            }
            self.sessionID = initialSessionID
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    public func apply(_ event: CodexSessionLogEvent) throws {
        var activityToPersist: CodexTaskActivity?

        switch event {
        case let .sessionDiscovered(sessionID, workingDirectory):
            self.sessionID = sessionID
            sessionWorkingDirectory = workingDirectory

        case let .turnContext(turnID, model, effort, workingDirectory):
            currentTurnID = turnID
            contexts[turnID] = TurnContext(
                model: model,
                effort: effort,
                workingDirectory: workingDirectory
            )
            if var activity = activities[taskKey(for: turnID)] {
                activity.model = model ?? activity.model
                activity.effort = effort ?? activity.effort
                activity.workingDirectory = workingDirectory ?? activity.workingDirectory
                activities[activity.id] = activity
                activityToPersist = activity
            }

        case let .turnStarted(turnID, startedAt):
            currentTurnID = turnID
            var activity = activities[taskKey(for: turnID)] ?? makeActivity(
                turnID: turnID,
                context: contexts[turnID],
                status: .working
            )
            activity.startedAt = activity.startedAt ?? startedAt
            if !activity.status.isFinished {
                activity.status = .working
            }
            activity.lastEventAt = max(activity.lastEventAt ?? .distantPast, startedAt)
            activities[activity.id] = activity
            activityToPersist = activity
            try Self.insertStatusEvent(
                CodexTaskStatusEvent(sessionID: activity.sessionID, turnID: turnID, status: .working, occurredAt: startedAt),
                in: database.pointer
            )

        case let .currentTurnStatusChanged(status, occurredAt):
            guard let turnID = currentTurnID else { break }
            var activity = activities[taskKey(for: turnID)] ?? makeActivity(
                turnID: turnID,
                context: contexts[turnID],
                status: status
            )
            applyStatus(status, at: occurredAt, to: &activity)
            activities[activity.id] = activity
            activityToPersist = activity
            try Self.insertStatusEvent(
                CodexTaskStatusEvent(sessionID: activity.sessionID, turnID: turnID, status: status, occurredAt: occurredAt),
                in: database.pointer
            )

        case let .turnStatusChanged(turnID, status, occurredAt):
            var activity = activities[taskKey(for: turnID)] ?? makeActivity(
                turnID: turnID,
                context: contexts[turnID],
                status: status
            )
            applyStatus(status, at: occurredAt, to: &activity)
            activities[activity.id] = activity
            activityToPersist = activity
            try Self.insertStatusEvent(
                CodexTaskStatusEvent(sessionID: activity.sessionID, turnID: turnID, status: status, occurredAt: occurredAt),
                in: database.pointer
            )

        case let .turnNavigationContext(turnID, transcriptPath, terminalProgram, terminalSessionID, sourceBundleIdentifier):
            var activity = activities[taskKey(for: turnID)] ?? makeActivity(
                turnID: turnID,
                context: contexts[turnID],
                status: .queued
            )
            activity.transcriptPath = transcriptPath ?? activity.transcriptPath
            activity.terminalProgram = terminalProgram ?? activity.terminalProgram
            activity.terminalSessionID = terminalSessionID ?? activity.terminalSessionID
            activity.sourceBundleIdentifier = sourceBundleIdentifier ?? activity.sourceBundleIdentifier
            activities[activity.id] = activity
            activityToPersist = activity

        case let .turnCompleted(turnID, completedAt, duration, timeToFirstToken):
            var activity = activities[taskKey(for: turnID)] ?? makeActivity(
                turnID: turnID,
                context: contexts[turnID],
                status: .completed
            )
            activity.status = .completed
            activity.completedAt = completedAt
            activity.duration = duration
            activity.timeToFirstToken = timeToFirstToken
            closeWaiting(at: completedAt, activity: &activity)
            activity.lastEventAt = max(activity.lastEventAt ?? .distantPast, completedAt)
            activities[activity.id] = activity
            activityToPersist = activity
            try Self.insertStatusEvent(
                CodexTaskStatusEvent(sessionID: activity.sessionID, turnID: turnID, status: .completed, occurredAt: completedAt),
                in: database.pointer
            )
        }

        if let activity = activityToPersist {
            try Self.upsert(activity, in: database.pointer)
        }
    }

    public func tasks() throws -> [CodexTaskActivity] {
        let result = Self.deduplicated(try Self.loadActivities(from: database.pointer))
        try Self.migrateStatusEvents(result.statusEventMigrations, in: database.pointer)
        activities = result.activities
        return activities.values.sorted { left, right in
            (left.startedAt ?? .distantPast) > (right.startedAt ?? .distantPast)
        }
    }

    public func statusEvents(since date: Date) throws -> [CodexTaskStatusEvent] {
        try Self.loadStatusEvents(since: date, from: database.pointer)
    }

    public func saveCheckIn(
        rating: CodexDailyWorkRating,
        rhythmScore: Int?,
        day: Date,
        calendar: Calendar = .current
    ) throws {
        try Self.upsertCheckIn(
            CodexDailyWorkCheckIn(
                day: calendar.startOfDay(for: day),
                rating: rating,
                rhythmScore: rhythmScore
            ),
            in: database.pointer
        )
    }

    public func checkIns(since date: Date) throws -> [CodexDailyWorkCheckIn] {
        try Self.loadCheckIns(since: date, from: database.pointer)
    }

    private func taskKey(for turnID: String) -> String {
        "\(sessionID):\(turnID)"
    }

    private func makeActivity(
        turnID: String,
        context: TurnContext?,
        status: CodexTaskStatus
    ) -> CodexTaskActivity {
        CodexTaskActivity(
            sessionID: sessionID,
            turnID: turnID,
            workingDirectory: context?.workingDirectory ?? sessionWorkingDirectory,
            model: context?.model,
            effort: context?.effort,
            status: status,
            startedAt: nil,
            completedAt: nil,
            duration: nil,
            timeToFirstToken: nil
        )
    }

    private func applyStatus(_ status: CodexTaskStatus, at date: Date, to activity: inout CodexTaskActivity) {
        if activity.status.isFinished, !status.isFinished {
            return
        }
        if activity.status.isWaitingForUser, !status.isWaitingForUser {
            closeWaiting(at: date, activity: &activity)
        } else if !activity.status.isWaitingForUser, status.isWaitingForUser {
            activity.waitingStartedAt = date
        }
        if activity.startedAt == nil, status.isActive {
            activity.startedAt = date
        }
        if status.isFinished {
            activity.completedAt = activity.completedAt ?? date
            if let startedAt = activity.startedAt {
                activity.duration = activity.duration ?? max(0, date.timeIntervalSince(startedAt))
            }
        }
        activity.status = status
        activity.lastEventAt = max(activity.lastEventAt ?? .distantPast, date)
    }

    private func closeWaiting(at date: Date, activity: inout CodexTaskActivity) {
        if let waitingStartedAt = activity.waitingStartedAt {
            activity.waitingDuration += max(0, date.timeIntervalSince(waitingStartedAt))
        }
        activity.waitingStartedAt = nil
    }

    private struct TurnContext: Sendable {
        let model: String?
        let effort: String?
        let workingDirectory: String?
    }

    private static func loadActivities(from database: OpaquePointer) throws -> [String: CodexTaskActivity] {
        let statement = try prepare("SELECT task_key, session_id, turn_id, working_directory, model, effort, status, started_at, completed_at, duration, time_to_first_token, last_event_at, waiting_started_at, waiting_duration, transcript_path, terminal_program, terminal_session_id, source_bundle_identifier FROM task_activity ORDER BY COALESCE(started_at, last_event_at) DESC LIMIT 5000;", on: database)
        defer { sqlite3_finalize(statement) }

        var activities: [String: CodexTaskActivity] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw TaskActivityStoreError.queryFailed(errorMessage(database))
            }

            guard let sessionID = stringColumn(statement, index: 1),
                  let turnID = stringColumn(statement, index: 2),
                  let statusRaw = stringColumn(statement, index: 6),
                  let status = CodexTaskStatus(rawValue: statusRaw)
            else {
                continue
            }

            let activity = CodexTaskActivity(
                sessionID: sessionID,
                turnID: turnID,
                workingDirectory: stringColumn(statement, index: 3),
                model: stringColumn(statement, index: 4),
                effort: stringColumn(statement, index: 5),
                status: status,
                startedAt: dateColumn(statement, index: 7),
                completedAt: dateColumn(statement, index: 8),
                duration: doubleColumn(statement, index: 9),
                timeToFirstToken: doubleColumn(statement, index: 10),
                lastEventAt: dateColumn(statement, index: 11),
                waitingStartedAt: dateColumn(statement, index: 12),
                waitingDuration: doubleColumn(statement, index: 13) ?? 0,
                transcriptPath: stringColumn(statement, index: 14),
                terminalProgram: stringColumn(statement, index: 15),
                terminalSessionID: stringColumn(statement, index: 16),
                sourceBundleIdentifier: stringColumn(statement, index: 17)
            )
            activities[activity.id] = activity
        }
        return activities
    }

    private static func secureDatabaseFiles(at databaseURL: URL) throws {
        let fileManager = FileManager.default
        let urls = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    private struct DeduplicationResult {
        var activities: [String: CodexTaskActivity]
        var statusEventMigrations: [String: CodexTaskActivity]
    }

    private static func deduplicated(
        _ loaded: [String: CodexTaskActivity]
    ) -> DeduplicationResult {
        var byTaskID: [String: CodexTaskActivity] = [:]
        var unknownTaskIDsByTurnID: [String: Set<String>] = [:]
        var statusEventMigrations: [String: CodexTaskActivity] = [:]
        for activity in loaded.values {
            let taskID = activity.id
            if activity.sessionID == "unknown" {
                let knownMatches = byTaskID.filter {
                    $0.value.sessionID != "unknown" && $0.value.turnID == activity.turnID
                }
                if knownMatches.count == 1,
                   let knownTaskID = knownMatches.keys.first,
                   let known = knownMatches.values.first {
                    byTaskID[knownTaskID] = merge(known, activity)
                    statusEventMigrations[taskID] = known
                } else if let existing = byTaskID[taskID] {
                    byTaskID[taskID] = merge(existing, activity)
                } else {
                    byTaskID[taskID] = activity
                    unknownTaskIDsByTurnID[activity.turnID, default: []].insert(taskID)
                }
                continue
            }

            if let unknownTaskIDs = unknownTaskIDsByTurnID.removeValue(forKey: activity.turnID),
               unknownTaskIDs.count == 1,
               let unknownTaskID = unknownTaskIDs.first,
               let unknown = byTaskID.removeValue(forKey: unknownTaskID) {
                byTaskID[taskID] = merge(unknown, activity)
                statusEventMigrations[unknownTaskID] = activity
            } else if let existing = byTaskID[taskID] {
                byTaskID[taskID] = merge(existing, activity)
            } else {
                byTaskID[taskID] = activity
            }
        }
        return DeduplicationResult(
            activities: byTaskID,
            statusEventMigrations: statusEventMigrations
        )
    }

    private static func merge(
        _ first: CodexTaskActivity,
        _ second: CodexTaskActivity
    ) -> CodexTaskActivity {
        let preferred: CodexTaskActivity
        if first.sessionID == "unknown", second.sessionID != "unknown" {
            preferred = second
        } else if second.sessionID == "unknown", first.sessionID != "unknown" {
            preferred = first
        } else if first.status.isFinished, !second.status.isFinished {
            preferred = first
        } else {
            preferred = second
        }

        let completed = [first, second]
            .filter { $0.status.isFinished }
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let starts = [first.startedAt, second.startedAt].compactMap { $0 }

        return CodexTaskActivity(
            sessionID: preferred.sessionID,
            turnID: preferred.turnID,
            workingDirectory: preferred.workingDirectory ?? first.workingDirectory ?? second.workingDirectory,
            model: preferred.model ?? first.model ?? second.model,
            effort: preferred.effort ?? first.effort ?? second.effort,
            status: completed?.status ?? preferred.status,
            startedAt: starts.min(),
            completedAt: completed?.completedAt,
            duration: completed?.duration,
            timeToFirstToken: completed?.timeToFirstToken,
            lastEventAt: [first.lastEventAt, second.lastEventAt].compactMap { $0 }.max(),
            waitingStartedAt: preferred.waitingStartedAt,
            waitingDuration: max(first.waitingDuration, second.waitingDuration),
            transcriptPath: preferred.transcriptPath ?? first.transcriptPath ?? second.transcriptPath,
            terminalProgram: preferred.terminalProgram ?? first.terminalProgram ?? second.terminalProgram,
            terminalSessionID: preferred.terminalSessionID ?? first.terminalSessionID ?? second.terminalSessionID,
            sourceBundleIdentifier: preferred.sourceBundleIdentifier ?? first.sourceBundleIdentifier ?? second.sourceBundleIdentifier
        )
    }

    private static func migrateStatusEvents(
        _ migrations: [String: CodexTaskActivity],
        in database: OpaquePointer
    ) throws {
        for (oldTaskKey, knownActivity) in migrations {
            let insert = try prepare(
                """
                INSERT OR IGNORE INTO task_status_event (
                    task_key, session_id, turn_id, status, occurred_at
                )
                SELECT ?, ?, turn_id, status, occurred_at
                FROM task_status_event
                WHERE task_key = ?;
                """,
                on: database
            )
            defer { sqlite3_finalize(insert) }
            try bind(knownActivity.id, to: insert, index: 1)
            try bind(knownActivity.sessionID, to: insert, index: 2)
            try bind(oldTaskKey, to: insert, index: 3)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw TaskActivityStoreError.queryFailed(errorMessage(database))
            }

            let delete = try prepare(
                "DELETE FROM task_status_event WHERE task_key = ?;",
                on: database
            )
            defer { sqlite3_finalize(delete) }
            try bind(oldTaskKey, to: delete, index: 1)
            guard sqlite3_step(delete) == SQLITE_DONE else {
                throw TaskActivityStoreError.queryFailed(errorMessage(database))
            }
        }
    }

    private static func upsert(_ activity: CodexTaskActivity, in database: OpaquePointer) throws {
        let sql = """
        INSERT INTO task_activity (task_key, session_id, turn_id, working_directory, model, effort, status, started_at, completed_at, duration, time_to_first_token, last_event_at, waiting_started_at, waiting_duration, transcript_path, terminal_program, terminal_session_id, source_bundle_identifier)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(task_key) DO UPDATE SET
            session_id = excluded.session_id,
            turn_id = excluded.turn_id,
            working_directory = excluded.working_directory,
            model = excluded.model,
            effort = excluded.effort,
            status = excluded.status,
            started_at = excluded.started_at,
            completed_at = excluded.completed_at,
            duration = excluded.duration,
            time_to_first_token = excluded.time_to_first_token,
            last_event_at = excluded.last_event_at,
            waiting_started_at = excluded.waiting_started_at,
            waiting_duration = excluded.waiting_duration,
            transcript_path = excluded.transcript_path,
            terminal_program = excluded.terminal_program,
            terminal_session_id = excluded.terminal_session_id,
            source_bundle_identifier = excluded.source_bundle_identifier;
        """
        let statement = try prepare(sql, on: database)
        defer { sqlite3_finalize(statement) }

        try bind(activity.id, to: statement, index: 1)
        try bind(activity.sessionID, to: statement, index: 2)
        try bind(activity.turnID, to: statement, index: 3)
        try bind(activity.workingDirectory, to: statement, index: 4)
        try bind(activity.model, to: statement, index: 5)
        try bind(activity.effort, to: statement, index: 6)
        try bind(activity.status.rawValue, to: statement, index: 7)
        try bind(activity.startedAt?.timeIntervalSince1970, to: statement, index: 8)
        try bind(activity.completedAt?.timeIntervalSince1970, to: statement, index: 9)
        try bind(activity.duration, to: statement, index: 10)
        try bind(activity.timeToFirstToken, to: statement, index: 11)
        try bind(activity.lastEventAt?.timeIntervalSince1970, to: statement, index: 12)
        try bind(activity.waitingStartedAt?.timeIntervalSince1970, to: statement, index: 13)
        try bind(activity.waitingDuration, to: statement, index: 14)
        try bind(activity.transcriptPath, to: statement, index: 15)
        try bind(activity.terminalProgram, to: statement, index: 16)
        try bind(activity.terminalSessionID, to: statement, index: 17)
        try bind(activity.sourceBundleIdentifier, to: statement, index: 18)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(Self.errorMessage(database))
        }
    }

    private static func insertStatusEvent(_ event: CodexTaskStatusEvent, in database: OpaquePointer) throws {
        let statement = try prepare("INSERT OR IGNORE INTO task_status_event (task_key, session_id, turn_id, status, occurred_at) VALUES (?, ?, ?, ?, ?);", on: database)
        defer { sqlite3_finalize(statement) }
        try bind(event.taskID, to: statement, index: 1)
        try bind(event.sessionID, to: statement, index: 2)
        try bind(event.turnID, to: statement, index: 3)
        try bind(event.status.rawValue, to: statement, index: 4)
        try bind(event.occurredAt.timeIntervalSince1970, to: statement, index: 5)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(errorMessage(database))
        }
    }

    private static func loadStatusEvents(since date: Date, from database: OpaquePointer) throws -> [CodexTaskStatusEvent] {
        let statement = try prepare(
            """
            SELECT session_id, turn_id, status, occurred_at
            FROM task_status_event
            WHERE occurred_at >= ?
            UNION ALL
            SELECT previous.session_id, previous.turn_id, previous.status, previous.occurred_at
            FROM task_status_event AS previous
            WHERE previous.occurred_at = (
                SELECT MAX(candidate.occurred_at)
                FROM task_status_event AS candidate
                WHERE candidate.task_key = previous.task_key
                  AND candidate.occurred_at < ?
            )
            ORDER BY occurred_at;
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(date.timeIntervalSince1970, to: statement, index: 1)
        try bind(date.timeIntervalSince1970, to: statement, index: 2)
        var events: [CodexTaskStatusEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionID = stringColumn(statement, index: 0),
                  let turnID = stringColumn(statement, index: 1),
                  let rawStatus = stringColumn(statement, index: 2),
                  let status = CodexTaskStatus(rawValue: rawStatus),
                  let occurredAt = dateColumn(statement, index: 3)
            else { continue }
            events.append(CodexTaskStatusEvent(sessionID: sessionID, turnID: turnID, status: status, occurredAt: occurredAt))
        }
        return events
    }

    private static func upsertCheckIn(_ checkIn: CodexDailyWorkCheckIn, in database: OpaquePointer) throws {
        let statement = try prepare("INSERT INTO daily_work_checkin (day_start, rating, rhythm_score) VALUES (?, ?, ?) ON CONFLICT(day_start) DO UPDATE SET rating = excluded.rating, rhythm_score = excluded.rhythm_score;", on: database)
        defer { sqlite3_finalize(statement) }
        try bind(checkIn.day.timeIntervalSince1970, to: statement, index: 1)
        try bind(checkIn.rating.rawValue, to: statement, index: 2)
        try bind(checkIn.rhythmScore.map(Double.init), to: statement, index: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(errorMessage(database))
        }
    }

    private static func loadCheckIns(since date: Date, from database: OpaquePointer) throws -> [CodexDailyWorkCheckIn] {
        let statement = try prepare("SELECT day_start, rating, rhythm_score FROM daily_work_checkin WHERE day_start >= ? ORDER BY day_start;", on: database)
        defer { sqlite3_finalize(statement) }
        try bind(date.timeIntervalSince1970, to: statement, index: 1)
        var checkIns: [CodexDailyWorkCheckIn] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let day = dateColumn(statement, index: 0),
                  let rawRating = stringColumn(statement, index: 1),
                  let rating = CodexDailyWorkRating(rawValue: rawRating)
            else { continue }
            checkIns.append(CodexDailyWorkCheckIn(day: day, rating: rating, rhythmScore: doubleColumn(statement, index: 2).map(Int.init)))
        }
        return checkIns
    }

    private static func migrateLegacySchema(on database: OpaquePointer) throws {
        let columns: [(String, String)] = [
            ("last_event_at", "REAL"),
            ("waiting_started_at", "REAL"),
            ("waiting_duration", "REAL NOT NULL DEFAULT 0"),
            ("transcript_path", "TEXT"),
            ("terminal_program", "TEXT"),
            ("terminal_session_id", "TEXT"),
            ("source_bundle_identifier", "TEXT")
        ]
        let existing = try tableColumns("task_activity", on: database)
        for (name, definition) in columns where !existing.contains(name) {
            try execute("ALTER TABLE task_activity ADD COLUMN \(name) \(definition);", on: database)
        }
    }

    private static func tableColumns(_ table: String, on database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table));", on: database)
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = stringColumn(statement, index: 1) { columns.insert(name) }
        }
        return columns
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw TaskActivityStoreError.queryFailed(message)
        }
    }

    private static func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw TaskActivityStoreError.queryFailed(errorMessage(database))
        }
        return statement
    }

    private static func bind(_ value: String?, to statement: OpaquePointer, index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw TaskActivityStoreError.queryFailed("Could not bind SQLite text value")
        }
    }

    private static func bind(_ value: Double?, to statement: OpaquePointer, index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw TaskActivityStoreError.queryFailed("Could not bind SQLite number value")
        }
    }

    private static func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func dateColumn(_ statement: OpaquePointer, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func doubleColumn(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private static func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

public enum TaskActivityStoreError: Error, Equatable, Sendable {
    case openFailed(String)
    case queryFailed(String)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
