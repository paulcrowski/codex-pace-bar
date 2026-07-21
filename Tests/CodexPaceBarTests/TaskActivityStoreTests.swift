import CodexPaceBarAppSupport
import CodexPaceBarCore
import Foundation
import SQLite3
import Testing

struct TaskActivityStoreTests {
    @Test
    func clearHistoryRemovesTasksEventsAndCheckIns() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")
        let now = Date()
        try await store.apply(.turnStarted(turnID: "turn", startedAt: now))
        try await store.apply(.turnCompleted(
            turnID: "turn",
            completedAt: now.addingTimeInterval(10),
            duration: 10,
            timeToFirstToken: nil
        ))
        try await store.saveCheckIn(rating: .calm, rhythmScore: 50, day: now)

        try await store.clearHistory()

        #expect(try await store.tasks().isEmpty)
        #expect(try await store.statusEvents(since: now.addingTimeInterval(-1)).isEmpty)
        #expect(try await store.checkIns(since: now.addingTimeInterval(-1)).isEmpty)
    }

    @Test
    func databaseFilesUseOwnerOnlyPermissions() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let store = try TaskActivityStore(databaseURL: databaseURL)
        try await store.apply(.sessionDiscovered(sessionID: "session", workingDirectory: "/work/project"))
        try await store.apply(.turnStarted(turnID: "turn", startedAt: Date()))

        let protectedURLs = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
        for url in protectedURLs where FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.intValue & 0o777 == 0o600)
        }
    }

    @Test
    func persistsTaskMetadataAndReloadsIt() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let startedAt = Date(timeIntervalSince1970: 1_784_372_923)
        let completedAt = Date(timeIntervalSince1970: 1_784_373_261)
        let store = try TaskActivityStore(databaseURL: databaseURL)

        try await store.apply(.sessionDiscovered(
            sessionID: "session-1",
            workingDirectory: "/work/project"
        ))
        try await store.apply(.turnContext(
            turnID: "turn-1",
            model: "gpt-5.6",
            effort: "high",
            workingDirectory: "/work/project"
        ))
        try await store.apply(.turnStarted(turnID: "turn-1", startedAt: startedAt))
        try await store.apply(.turnCompleted(
            turnID: "turn-1",
            completedAt: completedAt,
            duration: 338,
            timeToFirstToken: 4.589
        ))

        let expected = CodexTaskActivity(
            sessionID: "session-1",
            turnID: "turn-1",
            workingDirectory: "/work/project",
            model: "gpt-5.6",
            effort: "high",
            status: .completed,
            startedAt: startedAt,
            completedAt: completedAt,
            duration: 338,
            timeToFirstToken: 4.589,
            lastEventAt: completedAt
        )
        #expect(try await store.tasks() == [expected])
    }

    @Test
    func recordsWaitingTimeStatusTimelineAndDailyCheckIn() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let start = Date(timeIntervalSince1970: 1_784_372_000)
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")

        try await store.apply(.turnStatusChanged(turnID: "turn", status: .working, occurredAt: start))
        try await store.apply(.turnStatusChanged(turnID: "turn", status: .needsApproval, occurredAt: start.addingTimeInterval(60)))
        try await store.apply(.turnStatusChanged(turnID: "turn", status: .working, occurredAt: start.addingTimeInterval(180)))
        try await store.apply(.turnStatusChanged(turnID: "turn", status: .completed, occurredAt: start.addingTimeInterval(300)))
        try await store.saveCheckIn(rating: .intense, rhythmScore: 57, day: start)

        let task = try #require(await store.tasks().first)
        #expect(task.status == .completed)
        #expect(task.waitingDuration == 120)
        #expect(task.duration == 300)
        #expect(try await store.statusEvents(since: start).map(\.status) == [.working, .needsApproval, .working, .completed])
        #expect(try await store.checkIns(since: start.addingTimeInterval(-86_400)).first?.rating == .intense)
        #expect(try await store.checkIns(since: start.addingTimeInterval(-86_400)).first?.rhythmScore == 57)
    }

    @Test
    func persistsGoalLifecycleAndSwarmAggregateAcrossReload() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let start = Date(timeIntervalSince1970: 1_784_372_000)
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")

        try await store.apply(.sessionDiscovered(sessionID: "session", workingDirectory: "/work/project"))
        try await store.apply(.turnContext(
            turnID: "turn",
            model: "gpt-5.6",
            effort: "high",
            workingDirectory: "/work/project"
        ))
        try await store.apply(.turnStarted(turnID: "turn", startedAt: start))
        try await store.apply(.goalUpdated(CodexGoalActivity(
            threadID: "session",
            createdAt: start,
            updatedAt: start.addingTimeInterval(60),
            status: .active,
            activeDuration: 60,
            workingDirectory: "/work/project"
        )))
        try await store.apply(.swarmAgentSpawned(occurredAt: start.addingTimeInterval(70)))
        try await store.apply(.swarmAgentSpawned(occurredAt: start.addingTimeInterval(71)))
        try await store.apply(.turnCompleted(
            turnID: "turn",
            completedAt: start.addingTimeInterval(120),
            duration: 120,
            timeToFirstToken: nil
        ))
        try await store.apply(.goalUpdated(CodexGoalActivity(
            threadID: "session",
            createdAt: start,
            updatedAt: start.addingTimeInterval(120),
            status: .complete,
            activeDuration: 120,
            workingDirectory: "/work/project"
        )))

        let restartedStore = try TaskActivityStore(databaseURL: databaseURL)
        let goal = try #require(await restartedStore.goals().first)
        let swarm = try #require(await restartedStore.swarms().first)
        #expect(goal.status == .complete)
        #expect(goal.activeDuration == 120)
        #expect(swarm.agentCount == 2)
        #expect(swarm.duration == 50)
    }

    @Test
    func keepsCompletedGoalsForFortyFiveDaysButPrunesOlderHistory() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let now = Date()
        let store = try TaskActivityStore(databaseURL: databaseURL)

        let recentGoal = CodexGoalActivity(
            threadID: "recent",
            createdAt: now.addingTimeInterval(-40 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-40 * 24 * 60 * 60),
            status: .complete,
            activeDuration: 120
        )
        let oldGoal = CodexGoalActivity(
            threadID: "old",
            createdAt: now.addingTimeInterval(-46 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-46 * 24 * 60 * 60),
            status: .complete,
            activeDuration: 120
        )
        let longRunningGoal = CodexGoalActivity(
            threadID: "active",
            createdAt: now.addingTimeInterval(-46 * 24 * 60 * 60),
            updatedAt: now,
            status: .active,
            activeDuration: 120
        )
        try await store.apply(.goalUpdated(recentGoal))
        try await store.apply(.goalUpdated(oldGoal))
        try await store.apply(.goalUpdated(longRunningGoal))

        let restartedStore = try TaskActivityStore(databaseURL: databaseURL)
        let goals = try await restartedStore.goals()

        #expect(goals.contains { $0.threadID == "recent" })
        #expect(!goals.contains { $0.threadID == "old" })
        #expect(goals.contains { $0.threadID == "active" })
    }

    @Test
    func linksForecastObservationToTerminalGoalOutcome() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let start = Date(timeIntervalSince1970: 1_784_372_000)
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")
        let goal = CodexGoalActivity(
            threadID: "session",
            createdAt: start,
            updatedAt: start.addingTimeInterval(30),
            status: .active,
            activeDuration: 30
        )
        try await store.apply(.goalUpdated(goal))
        try await store.recordForecast(CodexForecastObservation(
            id: "goal:\(goal.id):0",
            entityType: .goal,
            entityID: goal.id,
            observedAt: start.addingTimeInterval(30),
            elapsedDuration: 30,
            medianRemaining: 60,
            safeRemaining: 120,
            probabilityWithinHorizon: 0.8,
            horizon: 1_800,
            sampleCount: 12,
            scope: .project
        ))

        #expect(try await store.forecastObservations().first?.actualDuration == nil)
        try await store.apply(.goalUpdated(CodexGoalActivity(
            threadID: "session",
            createdAt: start,
            updatedAt: start.addingTimeInterval(150),
            status: .blocked,
            activeDuration: 150
        )))

        let observation = try #require(await store.forecastObservations().first)
        #expect(observation.actualDuration == 150)
        #expect(observation.actualStatus == "blocked")
    }

    @Test
    func laterTurnContextBackfillsMissingProjectMetadata() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")

        try await store.apply(.turnStarted(
            turnID: "019f78ed-4da6-7fe0-b12a-8e92ebefd000",
            startedAt: Date(timeIntervalSince1970: 1_784_372_923)
        ))
        #expect(try await store.tasks().first?.workingDirectory == nil)

        try await store.apply(.turnContext(
            turnID: "019f78ed-4da6-7fe0-b12a-8e92ebefd000",
            model: "gpt-5.6",
            effort: "high",
            workingDirectory: "/work/codex-pace-bar"
        ))

        let task = try #require(await store.tasks().first)
        #expect(task.workingDirectory == "/work/codex-pace-bar")
        #expect(task.model == "gpt-5.6")
        #expect(task.effort == "high")
    }

    @Test
    func restartLoadsTheSameMetadata() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        do {
            let store = try TaskActivityStore(databaseURL: databaseURL)
            try await store.apply(.sessionDiscovered(
                sessionID: "session-1",
                workingDirectory: "/work/project"
            ))
            try await store.apply(.turnStarted(
                turnID: "turn-1",
                startedAt: Date(timeIntervalSince1970: 1_784_372_923)
            ))
        }

        let restartedStore = try TaskActivityStore(databaseURL: databaseURL)
        let tasks = try await restartedStore.tasks()

        #expect(tasks.count == 1)
        #expect(tasks.first?.status == .working)
        #expect(tasks.first?.turnID == "turn-1")
    }

    @Test
    func separateSessionStoresShareTheSameDatabase() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let firstStore = try TaskActivityStore(databaseURL: databaseURL)
        let secondStore = try TaskActivityStore(databaseURL: databaseURL)
        try await firstStore.apply(.sessionDiscovered(sessionID: "session-1", workingDirectory: "/one"))
        try await firstStore.apply(.turnStarted(
            turnID: "turn-1",
            startedAt: Date(timeIntervalSince1970: 1_784_372_923)
        ))
        try await secondStore.apply(.sessionDiscovered(sessionID: "session-2", workingDirectory: "/two"))
        try await secondStore.apply(.turnStarted(
            turnID: "turn-2",
            startedAt: Date(timeIntervalSince1970: 1_784_372_924)
        ))

        let tasks = try await firstStore.tasks()
        #expect(tasks.map(\.sessionID).sorted() == ["session-1", "session-2"])
    }

    @Test
    func knownSessionMergesDuplicateUnknownTurn() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let startedAt = Date(timeIntervalSince1970: 1_784_372_923)
        let completedAt = startedAt.addingTimeInterval(120)

        let unknownStore = try TaskActivityStore(databaseURL: databaseURL)
        try await unknownStore.apply(.turnStarted(turnID: "turn-1", startedAt: startedAt))
        try await unknownStore.apply(.turnStatusChanged(
            turnID: "turn-1",
            status: .needsApproval,
            occurredAt: startedAt.addingTimeInterval(60)
        ))
        try await unknownStore.apply(.turnCompleted(
            turnID: "turn-1",
            completedAt: completedAt,
            duration: 120,
            timeToFirstToken: 5
        ))

        let knownStore = try TaskActivityStore(
            databaseURL: databaseURL,
            initialSessionID: "session-1"
        )
        try await knownStore.apply(.turnStarted(turnID: "turn-1", startedAt: startedAt))
        let tasks = try await knownStore.tasks()

        #expect(tasks.count == 1)
        #expect(tasks.first?.sessionID == "session-1")
        #expect(tasks.first?.status == .completed)
        #expect(tasks.first?.duration == 120)
        let events = try await knownStore.statusEvents(since: startedAt.addingTimeInterval(-1))
        #expect(events.map(\.sessionID) == ["session-1", "session-1", "session-1"])
        #expect(events.map(\.status) == [.working, .needsApproval, .completed])
    }

    @Test
    func sameTurnIDAcrossSessionsRemainsTwoTasks() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let firstStartedAt = Date(timeIntervalSince1970: 1_784_372_923)
        let secondStartedAt = firstStartedAt.addingTimeInterval(1)

        let firstStore = try TaskActivityStore(
            databaseURL: databaseURL,
            initialSessionID: "session-1"
        )
        let secondStore = try TaskActivityStore(
            databaseURL: databaseURL,
            initialSessionID: "session-2"
        )
        try await firstStore.apply(.turnStarted(turnID: "same-turn", startedAt: firstStartedAt))
        try await secondStore.apply(.turnStarted(turnID: "same-turn", startedAt: secondStartedAt))

        let tasks = try await firstStore.tasks()
        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.id)) == Set(["session-1:same-turn", "session-2:same-turn"]))
    }

    @Test
    func repeatedLogEventsDoNotDuplicateStatusHistoryOrWaitingTime() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let start = Date(timeIntervalSince1970: 1_784_372_000)
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")

        try await store.apply(.turnStarted(turnID: "turn", startedAt: start))
        try await store.apply(.turnStarted(turnID: "turn", startedAt: start))
        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .needsApproval,
            occurredAt: start.addingTimeInterval(60)
        ))
        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .needsApproval,
            occurredAt: start.addingTimeInterval(60)
        ))
        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .completed,
            occurredAt: start.addingTimeInterval(180)
        ))
        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .completed,
            occurredAt: start.addingTimeInterval(180)
        ))

        let task = try #require(await store.tasks().first)
        #expect(task.id == "session:turn")
        #expect(task.waitingDuration == 120)
        #expect(try await store.statusEvents(since: start).count == 3)
    }

    @Test
    func statusEventsIncludeTheLastStateBeforeTheRequestedDay() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let dayStart = Date(timeIntervalSince1970: 1_784_376_000)
        let store = try TaskActivityStore(databaseURL: databaseURL, initialSessionID: "session")

        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .working,
            occurredAt: dayStart.addingTimeInterval(-3_600)
        ))
        try await store.apply(.turnStatusChanged(
            turnID: "turn",
            status: .completed,
            occurredAt: dayStart.addingTimeInterval(3_600)
        ))

        let events = try await store.statusEvents(since: dayStart)
        #expect(events.map(\.status) == [.working, .completed])
        #expect(events.first?.occurredAt == dayStart.addingTimeInterval(-3_600))
    }

    @Test
    func upgradesThePreviousSchemaBeforeReadingExistingTasks() async throws {
        let databaseURL = try makeDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        #expect(sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let legacySchema = """
        CREATE TABLE task_activity (
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
            time_to_first_token REAL
        );
        INSERT INTO task_activity (
            task_key, session_id, turn_id, working_directory, model, effort, status,
            started_at, completed_at, duration, time_to_first_token
        ) VALUES (
            'session:legacy-turn', 'session', 'legacy-turn', '/work/project',
            'gpt-5.6', 'high', 'completed', 1784372923, 1784373043, 120, 5
        );
        """
        #expect(sqlite3_exec(database, legacySchema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        database = nil

        let store = try TaskActivityStore(databaseURL: databaseURL)
        let task = try #require(await store.tasks().first)
        #expect(task.id == "session:legacy-turn")
        #expect(task.waitingDuration == 0)
        #expect(task.transcriptPath == nil)
    }

    private func makeDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tasks.sqlite")
    }
}
