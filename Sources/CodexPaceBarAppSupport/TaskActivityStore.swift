import CodexPaceBarCore
import Foundation
import SQLite3

public actor TaskActivityStore {
    public static let retentionDuration: TimeInterval = 30 * 24 * 60 * 60
    public static let goalRetentionDuration: TimeInterval = 45 * 24 * 60 * 60
    public static let checkInRetentionDuration: TimeInterval = 90 * 24 * 60 * 60

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
    CREATE TABLE IF NOT EXISTS goal_activity (
        goal_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        status TEXT NOT NULL,
        active_duration REAL NOT NULL,
        working_directory TEXT
    );
    CREATE TABLE IF NOT EXISTS swarm_activity (
        parent_task_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        turn_id TEXT NOT NULL,
        first_spawned_at REAL NOT NULL,
        agent_count INTEGER NOT NULL,
        completed_at REAL,
        working_directory TEXT
    );
    CREATE TABLE IF NOT EXISTS forecast_observation (
        observation_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        observed_at REAL NOT NULL,
        elapsed_duration REAL NOT NULL,
        median_remaining REAL,
        safe_remaining REAL,
        probability REAL,
        horizon REAL,
        sample_count INTEGER NOT NULL,
        scope TEXT NOT NULL,
        actual_duration REAL,
        actual_status TEXT,
        typical_total REAL,
        upper_total REAL,
        safe_away_remaining REAL,
        model TEXT NOT NULL DEFAULT 'baseline'
    );
    CREATE TABLE IF NOT EXISTS task_initial_plan (
        task_key TEXT PRIMARY KEY,
        observed_at REAL NOT NULL,
        step_count INTEGER NOT NULL,
        work_unit_count INTEGER NOT NULL,
        verification_count INTEGER NOT NULL,
        build_count INTEGER NOT NULL,
        runtime_check_count INTEGER NOT NULL,
        repository_count INTEGER NOT NULL,
        planned_parallelism INTEGER NOT NULL,
        category TEXT NOT NULL,
        complexity TEXT NOT NULL,
        classifier_version INTEGER NOT NULL
    );
    """

    private let database: SQLiteConnection
    private var sessionID = "unknown"
    private var sessionWorkingDirectory: String?
    private var contexts: [String: TurnContext] = [:]
    private var currentTurnID: String?
    private var activities: [String: CodexTaskActivity]
    private var goalsByID: [String: CodexGoalActivity]
    private var swarmsByID: [String: CodexSwarmActivity]
    private var plansByTaskID: [String: CodexTaskPlanSnapshot]

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
            try Self.prune(
                olderThan: Date().addingTimeInterval(-Self.retentionDuration),
                checkInsOlderThan: Date().addingTimeInterval(-Self.checkInRetentionDuration),
                in: database
            )
            try Self.secureDatabaseFiles(at: databaseURL)
            self.database = SQLiteConnection(pointer: database)
            if loadExisting {
                let loaded = try Self.loadActivities(from: database)
                let result = Self.deduplicated(loaded)
                try Self.migrateStatusEvents(result.statusEventMigrations, in: database)
                self.activities = result.activities
                self.goalsByID = try Self.loadGoals(from: database)
                self.swarmsByID = try Self.loadSwarms(from: database)
                self.plansByTaskID = try Self.loadTaskPlans(from: database)
            } else {
                self.activities = [:]
                self.goalsByID = [:]
                self.swarmsByID = [:]
                self.plansByTaskID = [:]
            }
            self.sessionID = initialSessionID
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    public func apply(_ event: CodexSessionLogEvent) throws {
        var activityToPersist: CodexTaskActivity?
        var goalToPersist: CodexGoalActivity?
        var swarmToPersist: CodexSwarmActivity?

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
            try Self.markForecasts(
                entityType: .task,
                entityID: activity.id,
                actualDuration: max(0, duration - activity.waitingDuration),
                actualStatus: activity.status.rawValue,
                in: database.pointer
            )

            if var swarm = swarmsByID[activity.id], swarm.completedAt == nil {
                swarm.completedAt = completedAt
                swarmsByID[swarm.id] = swarm
                swarmToPersist = swarm
            }

        case let .turnPlanObserved(turnID, observedAt, features):
            let resolvedTurnID = turnID ?? currentTurnID
            guard let resolvedTurnID else { break }
            let taskID = taskKey(for: resolvedTurnID)
            guard plansByTaskID[taskID] == nil else { break }
            let snapshot = CodexTaskPlanSnapshot(
                taskID: taskID,
                observedAt: observedAt,
                features: features
            )
            plansByTaskID[taskID] = snapshot
            try Self.upsert(snapshot, in: database.pointer)

        case let .goalUpdated(goal):
            var merged = goalsByID[goal.id] ?? goal
            guard goal.updatedAt >= merged.updatedAt else { break }
            merged.updatedAt = goal.updatedAt
            merged.status = goal.status
            merged.activeDuration = max(merged.activeDuration, goal.activeDuration)
            merged.workingDirectory = goal.workingDirectory ?? sessionWorkingDirectory
            goalsByID[merged.id] = merged
            goalToPersist = merged

        case let .swarmAgentSpawned(occurredAt):
            guard let turnID = currentTurnID else { break }
            let parentTaskID = taskKey(for: turnID)
            if let existing = swarmsByID[parentTaskID],
               let completedAt = existing.completedAt,
               occurredAt <= completedAt {
                break
            }
            var swarm = swarmsByID[parentTaskID] ?? CodexSwarmActivity(
                parentTaskID: parentTaskID,
                sessionID: sessionID,
                turnID: turnID,
                firstSpawnedAt: occurredAt,
                agentCount: 1,
                workingDirectory: contexts[turnID]?.workingDirectory ?? sessionWorkingDirectory
            )
            swarm.firstSpawnedAt = min(swarm.firstSpawnedAt, occurredAt)
            if swarmsByID[parentTaskID] != nil {
                swarm.agentCount += 1
            }
            swarm.completedAt = nil
            swarmsByID[parentTaskID] = swarm
            swarmToPersist = swarm
        }

        if let activity = activityToPersist {
            try Self.upsert(activity, in: database.pointer)
        }
        if let goal = goalToPersist {
            try Self.upsert(goal, in: database.pointer)
            if goal.isTerminal {
                try Self.markForecasts(
                    entityType: .goal,
                    entityID: goal.id,
                    actualDuration: goal.activeDuration,
                    actualStatus: goal.status.rawValue,
                    in: database.pointer
                )
            }
        }
        if let swarm = swarmToPersist {
            try Self.upsert(swarm, in: database.pointer)
            if let duration = swarm.duration {
                try Self.markForecasts(
                    entityType: .swarm,
                    entityID: swarm.id,
                    actualDuration: duration,
                    actualStatus: "complete",
                    in: database.pointer
                )
            }
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

    public func goals() throws -> [CodexGoalActivity] {
        goalsByID = try Self.loadGoals(from: database.pointer)
        return goalsByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func swarms() throws -> [CodexSwarmActivity] {
        swarmsByID = try Self.loadSwarms(from: database.pointer)
        return swarmsByID.values.sorted { $0.firstSpawnedAt > $1.firstSpawnedAt }
    }

    public func taskPlans() throws -> [CodexTaskPlanSnapshot] {
        plansByTaskID = try Self.loadTaskPlans(from: database.pointer)
        return plansByTaskID.values.sorted { $0.observedAt > $1.observedAt }
    }

    public func recordForecast(_ observation: CodexForecastObservation) throws {
        let statement = try Self.prepare(
            """
            INSERT INTO forecast_observation (observation_id, entity_type, entity_id, observed_at, elapsed_duration, median_remaining, safe_remaining, probability, horizon, sample_count, scope, typical_total, upper_total, safe_away_remaining, model)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(observation_id) DO UPDATE SET
                median_remaining = excluded.median_remaining,
                safe_remaining = excluded.safe_remaining,
                probability = excluded.probability,
                horizon = excluded.horizon,
                sample_count = excluded.sample_count,
                scope = excluded.scope,
                typical_total = excluded.typical_total,
                upper_total = excluded.upper_total,
                safe_away_remaining = excluded.safe_away_remaining,
                model = excluded.model;
            """,
            on: database.pointer
        )
        defer { sqlite3_finalize(statement) }
        try Self.bind(observation.id, to: statement, index: 1)
        try Self.bind(observation.entityType.rawValue, to: statement, index: 2)
        try Self.bind(observation.entityID, to: statement, index: 3)
        try Self.bind(observation.observedAt.timeIntervalSince1970, to: statement, index: 4)
        try Self.bind(observation.elapsedDuration, to: statement, index: 5)
        try Self.bind(observation.medianRemaining, to: statement, index: 6)
        try Self.bind(observation.safeRemaining, to: statement, index: 7)
        try Self.bind(observation.probabilityWithinHorizon, to: statement, index: 8)
        try Self.bind(observation.horizon, to: statement, index: 9)
        try Self.bind(Double(observation.sampleCount), to: statement, index: 10)
        try Self.bind(observation.scope.rawValue, to: statement, index: 11)
        try Self.bind(observation.typicalTotal, to: statement, index: 12)
        try Self.bind(observation.upperTotal, to: statement, index: 13)
        try Self.bind(observation.safeAwayRemaining, to: statement, index: 14)
        try Self.bind(observation.model.rawValue, to: statement, index: 15)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(Self.errorMessage(database.pointer))
        }
    }

    public func forecastObservations(since date: Date? = nil) throws -> [CodexForecastObservation] {
        try Self.loadForecastObservations(since: date, from: database.pointer)
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

    public func clearHistory() throws {
        try Self.execute(
            "DELETE FROM task_status_event; DELETE FROM task_activity; DELETE FROM daily_work_checkin; DELETE FROM goal_activity; DELETE FROM swarm_activity; DELETE FROM forecast_observation; DELETE FROM task_initial_plan; PRAGMA wal_checkpoint(TRUNCATE);",
            on: database.pointer
        )
        activities.removeAll()
        goalsByID.removeAll()
        swarmsByID.removeAll()
        plansByTaskID.removeAll()
        contexts.removeAll()
        currentTurnID = nil
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

    private static func prune(
        olderThan cutoff: Date,
        checkInsOlderThan checkInCutoff: Date,
        in database: OpaquePointer
    ) throws {
        let taskCutoff = cutoff.timeIntervalSince1970
        let goalCutoff = Date().addingTimeInterval(-goalRetentionDuration).timeIntervalSince1970
        let checkInCutoff = checkInCutoff.timeIntervalSince1970
        try execute(
            """
            DELETE FROM task_status_event
            WHERE occurred_at < \(taskCutoff);
            DELETE FROM task_activity
            WHERE COALESCE(last_event_at, completed_at, started_at, 0) < \(taskCutoff)
              AND status NOT IN ('queued', 'working', 'needsApproval', 'needsInput');
            DELETE FROM daily_work_checkin WHERE day_start < \(checkInCutoff);
            DELETE FROM goal_activity
            WHERE updated_at < \(goalCutoff)
              AND status <> 'active';
            DELETE FROM swarm_activity
            WHERE COALESCE(completed_at, first_spawned_at, 0) < \(taskCutoff)
              AND completed_at IS NOT NULL;
            DELETE FROM forecast_observation WHERE observed_at < \(taskCutoff);
            DELETE FROM task_initial_plan WHERE observed_at < \(taskCutoff);
            """,
            on: database
        )
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

    private static func upsert(_ goal: CodexGoalActivity, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO goal_activity (goal_id, thread_id, created_at, updated_at, status, active_duration, working_directory)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(goal_id) DO UPDATE SET
                thread_id = excluded.thread_id,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                status = excluded.status,
                active_duration = excluded.active_duration,
                working_directory = excluded.working_directory;
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(goal.id, to: statement, index: 1)
        try bind(goal.threadID, to: statement, index: 2)
        try bind(goal.createdAt.timeIntervalSince1970, to: statement, index: 3)
        try bind(goal.updatedAt.timeIntervalSince1970, to: statement, index: 4)
        try bind(goal.status.rawValue, to: statement, index: 5)
        try bind(goal.activeDuration, to: statement, index: 6)
        try bind(goal.workingDirectory, to: statement, index: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(Self.errorMessage(database))
        }
    }

    private static func upsert(_ swarm: CodexSwarmActivity, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO swarm_activity (parent_task_id, session_id, turn_id, first_spawned_at, agent_count, completed_at, working_directory)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(parent_task_id) DO UPDATE SET
                session_id = excluded.session_id,
                turn_id = excluded.turn_id,
                first_spawned_at = excluded.first_spawned_at,
                agent_count = excluded.agent_count,
                completed_at = excluded.completed_at,
                working_directory = excluded.working_directory;
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(swarm.parentTaskID, to: statement, index: 1)
        try bind(swarm.sessionID, to: statement, index: 2)
        try bind(swarm.turnID, to: statement, index: 3)
        try bind(swarm.firstSpawnedAt.timeIntervalSince1970, to: statement, index: 4)
        try bind(Double(swarm.agentCount), to: statement, index: 5)
        try bind(swarm.completedAt?.timeIntervalSince1970, to: statement, index: 6)
        try bind(swarm.workingDirectory, to: statement, index: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(Self.errorMessage(database))
        }
    }

    private static func upsert(_ snapshot: CodexTaskPlanSnapshot, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO task_initial_plan (task_key, observed_at, step_count, work_unit_count, verification_count, build_count, runtime_check_count, repository_count, planned_parallelism, category, complexity, classifier_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_key) DO NOTHING;
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(snapshot.taskID, to: statement, index: 1)
        try bind(snapshot.observedAt.timeIntervalSince1970, to: statement, index: 2)
        try bind(Double(snapshot.features.stepCount), to: statement, index: 3)
        try bind(Double(snapshot.features.workUnitCount), to: statement, index: 4)
        try bind(Double(snapshot.features.verificationCount), to: statement, index: 5)
        try bind(Double(snapshot.features.buildCount), to: statement, index: 6)
        try bind(Double(snapshot.features.runtimeCheckCount), to: statement, index: 7)
        try bind(Double(snapshot.features.repositoryCount), to: statement, index: 8)
        try bind(Double(snapshot.features.plannedParallelism), to: statement, index: 9)
        try bind(snapshot.features.category.rawValue, to: statement, index: 10)
        try bind(snapshot.features.complexity.rawValue, to: statement, index: 11)
        try bind(Double(snapshot.features.classifierVersion), to: statement, index: 12)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(Self.errorMessage(database))
        }
    }

    private static func loadTaskPlans(from database: OpaquePointer) throws -> [String: CodexTaskPlanSnapshot] {
        let statement = try prepare(
            "SELECT task_key, observed_at, step_count, work_unit_count, verification_count, build_count, runtime_check_count, repository_count, planned_parallelism, category, complexity, classifier_version FROM task_initial_plan ORDER BY observed_at DESC LIMIT 5000;",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        var snapshots: [String: CodexTaskPlanSnapshot] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let taskID = stringColumn(statement, index: 0),
                  let observedAt = dateColumn(statement, index: 1),
                  let categoryRaw = stringColumn(statement, index: 9),
                  let category = CodexTaskCategory(rawValue: categoryRaw),
                  let complexityRaw = stringColumn(statement, index: 10),
                  let complexity = CodexTaskComplexity(rawValue: complexityRaw)
            else { continue }
            let features = CodexTaskPlanFeatures(
                stepCount: Int(doubleColumn(statement, index: 2) ?? 0),
                workUnitCount: Int(doubleColumn(statement, index: 3) ?? 0),
                verificationCount: Int(doubleColumn(statement, index: 4) ?? 0),
                buildCount: Int(doubleColumn(statement, index: 5) ?? 0),
                runtimeCheckCount: Int(doubleColumn(statement, index: 6) ?? 0),
                repositoryCount: Int(doubleColumn(statement, index: 7) ?? 0),
                plannedParallelism: Int(doubleColumn(statement, index: 8) ?? 0),
                category: category,
                complexity: complexity,
                classifierVersion: Int(doubleColumn(statement, index: 11) ?? 1)
            )
            snapshots[taskID] = CodexTaskPlanSnapshot(
                taskID: taskID,
                observedAt: observedAt,
                features: features
            )
        }
        return snapshots
    }

    private static func loadGoals(from database: OpaquePointer) throws -> [String: CodexGoalActivity] {
        let statement = try prepare(
            "SELECT goal_id, thread_id, created_at, updated_at, status, active_duration, working_directory FROM goal_activity ORDER BY updated_at DESC;",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        var goals: [String: CodexGoalActivity] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let goalID = stringColumn(statement, index: 0),
                  let threadID = stringColumn(statement, index: 1),
                  let createdAt = dateColumn(statement, index: 2),
                  let updatedAt = dateColumn(statement, index: 3),
                  let rawStatus = stringColumn(statement, index: 4),
                  let status = CodexGoalStatus(rawValue: rawStatus),
                  let activeDuration = doubleColumn(statement, index: 5)
            else { continue }
            let goal = CodexGoalActivity(
                threadID: threadID,
                createdAt: createdAt,
                updatedAt: updatedAt,
                status: status,
                activeDuration: activeDuration,
                workingDirectory: stringColumn(statement, index: 6)
            )
            goals[goalID] = goal
        }
        return goals
    }

    private static func loadSwarms(from database: OpaquePointer) throws -> [String: CodexSwarmActivity] {
        let statement = try prepare(
            "SELECT parent_task_id, session_id, turn_id, first_spawned_at, agent_count, completed_at, working_directory FROM swarm_activity ORDER BY first_spawned_at DESC;",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        var swarms: [String: CodexSwarmActivity] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let parentTaskID = stringColumn(statement, index: 0),
                  let sessionID = stringColumn(statement, index: 1),
                  let turnID = stringColumn(statement, index: 2),
                  let firstSpawnedAt = dateColumn(statement, index: 3),
                  let agentCount = doubleColumn(statement, index: 4)
            else { continue }
            let swarm = CodexSwarmActivity(
                parentTaskID: parentTaskID,
                sessionID: sessionID,
                turnID: turnID,
                firstSpawnedAt: firstSpawnedAt,
                agentCount: Int(agentCount),
                completedAt: dateColumn(statement, index: 5),
                workingDirectory: stringColumn(statement, index: 6)
            )
            swarms[parentTaskID] = swarm
        }
        return swarms
    }

    private static func loadForecastObservations(
        since date: Date?,
        from database: OpaquePointer
    ) throws -> [CodexForecastObservation] {
        let statement = try prepare(
            """
            SELECT observation_id, entity_type, entity_id, observed_at, elapsed_duration,
                   median_remaining, safe_remaining, probability, horizon, sample_count,
                   scope, actual_duration, actual_status, typical_total, upper_total,
                   safe_away_remaining, model
            FROM forecast_observation
            WHERE (? IS NULL OR observed_at >= ?)
            ORDER BY observed_at ASC;
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        let timestamp = date?.timeIntervalSince1970
        try bind(timestamp, to: statement, index: 1)
        try bind(timestamp, to: statement, index: 2)

        var observations: [CodexForecastObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = stringColumn(statement, index: 0),
                  let rawEntityType = stringColumn(statement, index: 1),
                  let entityType = CodexForecastEntityType(rawValue: rawEntityType),
                  let entityID = stringColumn(statement, index: 2),
                  let observedAt = dateColumn(statement, index: 3),
                  let elapsedDuration = doubleColumn(statement, index: 4),
                  let rawScope = stringColumn(statement, index: 10),
                  let scope = CodexTaskDurationEstimateScope(rawValue: rawScope),
                  let sampleCount = doubleColumn(statement, index: 9)
            else { continue }
            observations.append(CodexForecastObservation(
                id: id,
                entityType: entityType,
                entityID: entityID,
                observedAt: observedAt,
                elapsedDuration: elapsedDuration,
                medianRemaining: doubleColumn(statement, index: 5),
                safeRemaining: doubleColumn(statement, index: 6),
                probabilityWithinHorizon: doubleColumn(statement, index: 7),
                horizon: doubleColumn(statement, index: 8),
                sampleCount: Int(sampleCount),
                scope: scope,
                typicalTotal: doubleColumn(statement, index: 13),
                upperTotal: doubleColumn(statement, index: 14),
                safeAwayRemaining: doubleColumn(statement, index: 15),
                model: stringColumn(statement, index: 16).flatMap(CodexTaskForecastModel.init(rawValue:)) ?? .baseline,
                actualDuration: doubleColumn(statement, index: 11),
                actualStatus: stringColumn(statement, index: 12)
            ))
        }
        return observations
    }

    private static func markForecasts(
        entityType: CodexForecastEntityType,
        entityID: String,
        actualDuration: TimeInterval,
        actualStatus: String,
        in database: OpaquePointer
    ) throws {
        let statement = try prepare(
            "UPDATE forecast_observation SET actual_duration = ?, actual_status = ? WHERE entity_type = ? AND entity_id = ? AND actual_duration IS NULL;",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(actualDuration, to: statement, index: 1)
        try bind(actualStatus, to: statement, index: 2)
        try bind(entityType.rawValue, to: statement, index: 3)
        try bind(entityID, to: statement, index: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskActivityStoreError.queryFailed(errorMessage(database))
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
        let forecastColumns: [(String, String)] = [
            ("typical_total", "REAL"),
            ("upper_total", "REAL"),
            ("safe_away_remaining", "REAL"),
            ("model", "TEXT NOT NULL DEFAULT 'baseline'")
        ]
        let existingForecast = try tableColumns("forecast_observation", on: database)
        for (name, definition) in forecastColumns where !existingForecast.contains(name) {
            try execute("ALTER TABLE forecast_observation ADD COLUMN \(name) \(definition);", on: database)
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
