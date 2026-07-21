import CodexPaceBarCore
import Darwin
import Foundation

@MainActor
public final class TaskMonitorCoordinator {
    public static var defaultDatabaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("task-activity.sqlite")
    }

    public static var defaultHookEventURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("task-hook-events.jsonl")
    }

    private let catalog: CodexSessionLogCatalog
    private let databaseURL: URL
    private let queryStore: TaskActivityStore
    private let watcherQueue: DispatchQueue
    private let hookEventURL: URL
    private let nativeGoalStore: CodexNativeGoalStore
    private var stores: [URL: TaskActivityStore] = [:]
    private var watchers: [URL: CodexSessionLogFileWatcher] = [:]
    private var directoryWatchers: [URL: CodexSessionLogDirectoryWatcher] = [:]
    private var hookEventWatcher: CodexHookEventWatcher?
    private var rescanTask: Task<Void, Never>?
    private var aggregateBackfillTask: Task<Void, Never>?
    private var isRunning = false

    public var onChange: (() -> Void)?
    public var onError: ((Error) -> Void)?

    public init(
        catalog: CodexSessionLogCatalog = CodexSessionLogCatalog(),
        databaseURL: URL = TaskMonitorCoordinator.defaultDatabaseURL,
        hookEventURL: URL? = nil,
        nativeGoalStore: CodexNativeGoalStore = CodexNativeGoalStore(),
        watcherQueue: DispatchQueue = DispatchQueue(
            label: "codex-pace-bar.task-monitor",
            qos: .utility
        )
    ) throws {
        self.catalog = catalog
        self.databaseURL = databaseURL
        self.watcherQueue = watcherQueue
        self.nativeGoalStore = nativeGoalStore
        self.hookEventURL = hookEventURL ?? (
            databaseURL == Self.defaultDatabaseURL
                ? Self.defaultHookEventURL
                : databaseURL.deletingLastPathComponent().appendingPathComponent("task-hook-events.jsonl")
        )
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        self.queryStore = try TaskActivityStore(databaseURL: databaseURL)
    }

    deinit {
        directoryWatchers.values.forEach { $0.stop() }
        watchers.values.forEach { $0.stop() }
        hookEventWatcher?.stop()
        aggregateBackfillTask?.cancel()
    }

    public func start() throws {
        guard !isRunning else {
            return
        }
        isRunning = true
        do {
            try startHookEventWatcher()
            try rescan()
            scheduleAggregateBackfillIfNeeded()
        } catch {
            isRunning = false
            throw error
        }
    }

    public func rescan() throws {
        guard isRunning else {
            return
        }
        rescanTask?.cancel()
        let catalog = self.catalog
        rescanTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let files = try catalog.recentLogFiles()
                guard !Task.isCancelled else { return }
                await self?.applyCatalogFiles(files)
            } catch {
                await self?.report(error)
            }
        }
    }

    private func scheduleAggregateBackfillIfNeeded() {
        guard aggregateBackfillTask == nil else { return }
        let markerURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("goal-swarm-backfill-v2.done")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }

        let catalog = self.catalog
        let queryStore = self.queryStore
        aggregateBackfillTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let candidateFiles = try catalog.recentLogFiles(
                    limit: 5_000,
                    maximumAge: TaskActivityStore.goalRetentionDuration
                )
                // A single long-running Codex session can be hundreds of MB.
                // Keep the first-run repair bounded so it cannot monopolize
                // the menu-bar app; normal live watchers continue filling new
                // aggregate rows after this pass.
                let files = try await aggregateBackfillFiles(candidateFiles)
                let parser = CodexSessionLogParser()
                for fileURL in files {
                    guard !Task.isCancelled else { return }
                    try await scanAggregateEvents(from: fileURL, parser: parser) { event in
                        try await queryStore.apply(event)
                    }
                }
                try Data("v1".utf8).write(to: markerURL, options: .atomic)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: markerURL.path
                )
                await MainActor.run {
                    self?.aggregateBackfillTask = nil
                    self?.onChange?()
                }
            } catch is CancellationError {
                await MainActor.run { self?.aggregateBackfillTask = nil }
            } catch {
                await MainActor.run {
                    self?.aggregateBackfillTask = nil
                    self?.onError?(error)
                }
            }
        }
    }

    private func applyCatalogFiles(_ files: [URL]) {
        guard isRunning else { return }
        let desiredFiles = Set(files)
        for fileURL in Array(watchers.keys) where !desiredFiles.contains(fileURL) {
            detach(fileURL: fileURL)
        }
        for fileURL in files {
            do {
                try attach(fileURL: fileURL)
            } catch {
                report(error)
            }
        }
        do {
            try synchronizeDirectoryWatchers(for: files)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        onError?(error)
    }

    public func stop() {
        isRunning = false
        rescanTask?.cancel()
        rescanTask = nil
        directoryWatchers.values.forEach { $0.stop() }
        directoryWatchers.removeAll()
        watchers.values.forEach { $0.stop() }
        hookEventWatcher?.stop()
        hookEventWatcher = nil
        watchers.removeAll()
        stores.removeAll()
    }

    public func tasks() async throws -> [CodexTaskActivity] {
        try await queryStore.tasks()
    }

    public func statusEvents(since date: Date) async throws -> [CodexTaskStatusEvent] {
        try await queryStore.statusEvents(since: date)
    }

    public func goals() async throws -> [CodexGoalActivity] {
        let loggedGoals = try await queryStore.goals()
        let nativeGoals = try nativeGoalStore.activeGoals()
        guard !nativeGoals.isEmpty else { return loggedGoals }

        var merged = loggedGoals
        for nativeGoal in nativeGoals {
            if let index = merged.firstIndex(where: { $0.threadID == nativeGoal.threadID }) {
                var existing = merged[index]
                guard nativeGoal.updatedAt >= existing.updatedAt else { continue }
                existing.updatedAt = nativeGoal.updatedAt
                existing.status = nativeGoal.status
                existing.activeDuration = nativeGoal.activeDuration
                merged[index] = existing
            } else {
                merged.append(nativeGoal)
            }
        }
        return merged.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func swarms() async throws -> [CodexSwarmActivity] {
        try await queryStore.swarms()
    }

    public func taskPlans() async throws -> [CodexTaskPlanSnapshot] {
        try await queryStore.taskPlans()
    }

    public func recordForecast(_ observation: CodexForecastObservation) async throws {
        try await queryStore.recordForecast(observation)
    }

    public func forecastObservations(since date: Date? = nil) async throws -> [CodexForecastObservation] {
        try await queryStore.forecastObservations(since: date)
    }

    public func checkIns(since date: Date) async throws -> [CodexDailyWorkCheckIn] {
        try await queryStore.checkIns(since: date)
    }

    public func clearHistory() async throws {
        try await queryStore.clearHistory()
        onChange?()
    }

    public func saveCheckIn(
        rating: CodexDailyWorkRating,
        rhythmScore: Int?,
        day: Date = Date()
    ) async throws {
        try await queryStore.saveCheckIn(rating: rating, rhythmScore: rhythmScore, day: day)
        onChange?()
    }

    private func attach(fileURL: URL) throws {
        guard watchers[fileURL] == nil else {
            return
        }

        let store = try TaskActivityStore(
            databaseURL: databaseURL,
            initialSessionID: catalog.sessionID(for: fileURL) ?? "unknown",
            loadExisting: false
        )
        let watcher = CodexSessionLogFileWatcher(
            fileURL: fileURL,
            queue: watcherQueue,
            onEvents: { [weak self] events in
                Task { @MainActor [weak self] in
                    await self?.apply(events, from: fileURL, using: store)
                }
            },
            onInvalidated: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.detach(fileURL: fileURL)
                }
            }
        )

        try watcher.start()
        stores[fileURL] = store
        watchers[fileURL] = watcher
    }

    private func synchronizeDirectoryWatchers(for files: [URL]) throws {
        let desiredDirectories = watchedDirectories(for: files)

        for directoryURL in Array(directoryWatchers.keys) where !desiredDirectories.contains(directoryURL) {
            directoryWatchers[directoryURL]?.stop()
            directoryWatchers.removeValue(forKey: directoryURL)
        }

        for directoryURL in desiredDirectories where directoryWatchers[directoryURL] == nil {
            let watcher = CodexSessionLogDirectoryWatcher(directoryURL: directoryURL) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else {
                        return
                    }
                    try? self.rescan()
                }
            }
            try watcher.start()
            directoryWatchers[directoryURL] = watcher
        }
    }

    private func watchedDirectories(for files: [URL]) -> Set<URL> {
        let rootURL = catalog.rootURL.standardizedFileURL
        let rootPath = rootURL.path
        var result: Set<URL> = [rootURL]

        for fileURL in files {
            var directoryURL = fileURL.deletingLastPathComponent().standardizedFileURL
            while directoryURL.path == rootPath || directoryURL.path.hasPrefix(rootPath + "/") {
                result.insert(directoryURL)
                guard directoryURL.path != rootPath else {
                    break
                }
                directoryURL = directoryURL.deletingLastPathComponent().standardizedFileURL
            }
        }

        return result
    }

    private func startHookEventWatcher() throws {
        guard hookEventWatcher == nil else { return }
        try FileManager.default.createDirectory(
            at: hookEventURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !FileManager.default.fileExists(atPath: hookEventURL.path) {
            FileManager.default.createFile(
                atPath: hookEventURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        try trimHookEventFileIfNeeded()
        let watcher = CodexHookEventWatcher(
            fileURL: hookEventURL,
            queue: watcherQueue,
            onEvents: { [weak self] events in
                Task { @MainActor [weak self] in
                    await self?.apply(events, from: self?.hookEventURL ?? URL(fileURLWithPath: ""), using: self?.queryStore)
                }
            },
            onInvalidated: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.hookEventWatcher = nil
                    try? self?.startHookEventWatcher()
                }
            }
        )
        try watcher.start()
        hookEventWatcher = watcher
    }

    private func trimHookEventFileIfNeeded() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: hookEventURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 2 * 1_024 * 1_024 else { return }
        let handle = try FileHandle(forReadingFrom: hookEventURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: size - 1_024 * 1_024)
        var tail = try handle.readToEnd() ?? Data()
        if let newline = tail.firstIndex(of: 0x0A) {
            tail.removeSubrange(tail.startIndex...newline)
        }
        try tail.write(to: hookEventURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hookEventURL.path)
    }

    private func detach(fileURL: URL) {
        watchers[fileURL]?.stop()
        watchers.removeValue(forKey: fileURL)
        stores.removeValue(forKey: fileURL)
    }

    private func apply(
        _ events: [CodexSessionLogEvent],
        from fileURL: URL,
        using store: TaskActivityStore?
    ) async {
        guard let store else { return }
        do {
            for event in events {
                try await store.apply(event)
            }
            _ = fileURL
            onChange?()
        } catch {
            onError?(error)
        }
    }
}

private let aggregateBackfillDiscoveryBudget: UInt64 = 1_024 * 1_024 * 1_024
private let aggregateBackfillByteBudget: UInt64 = 512 * 1_024 * 1_024
private let aggregateBackfillMaximumFileSize: UInt64 = 256 * 1_024 * 1_024

private func aggregateBackfillFiles(_ candidates: [URL]) async throws -> [URL] {
    var total: UInt64 = 0
    var discovered: UInt64 = 0
    var selected: [URL] = []
    for fileURL in candidates {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0
        else { continue }
        let byteSize = UInt64(size)
        guard discovered + byteSize <= aggregateBackfillDiscoveryBudget else { break }
        discovered += byteSize
        guard byteSize <= aggregateBackfillMaximumFileSize,
              try await fileContainsAggregateMarker(fileURL),
              total + byteSize <= aggregateBackfillByteBudget else { continue }
        selected.append(fileURL)
        total += byteSize
    }
    return selected
}

private func fileContainsAggregateMarker(_ fileURL: URL) async throws -> Bool {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var carry = Data()
    while let chunk = try handle.read(upToCount: 1 * 1_024 * 1_024), !chunk.isEmpty {
        try Task.checkCancellation()
        carry.append(chunk)
        if aggregateCandidateMarkers.contains(where: { carry.range(of: $0) != nil }) {
            return true
        }
        let keep = min(64, carry.count)
        carry = Data(carry.suffix(keep))
    }
    return false
}

private let aggregateCandidateMarkers = [
    Data("thread_goal_updated".utf8),
    Data("timeUsedSeconds".utf8),
    Data("spawn_agent".utf8)
]

private func scanAggregateEvents(
    from fileURL: URL,
    parser: CodexSessionLogParser,
    consume: (CodexSessionLogEvent) async throws -> Void
) async throws {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    var buffer = Data()
    var lineStart = buffer.startIndex
    while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
        try Task.checkCancellation()
        buffer.append(chunk)
        while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
            let line = buffer[lineStart..<newline]
            lineStart = buffer.index(after: newline)
            guard isAggregateLine(line), let event = parser.parseLine(Data(line)) else { continue }
            switch event {
            case .sessionDiscovered, .turnContext, .turnCompleted, .goalUpdated, .swarmAgentSpawned:
                try await consume(event)
            default:
                continue
            }
        }
        if lineStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<lineStart)
            lineStart = buffer.startIndex
        }
    }
}

private func isAggregateLine(_ line: Data) -> Bool {
    // Keep the one-time history pass cheap: large session logs contain the
    // word "goal" in prompts and instructions, but only these fields can
    // produce a native aggregate event.
    return aggregateLineMarkers.contains { line.range(of: $0) != nil }
}

private let aggregateLineMarkers = [
    Data("session_meta".utf8),
    Data("turn_context".utf8),
    Data("task_complete".utf8),
    Data("thread_goal_updated".utf8),
    Data("spawn_agent".utf8),
    Data("timeUsedSeconds".utf8)
]

private final class CodexHookEventWatcher: @unchecked Sendable {
    private let fileURL: URL
    private let queue: DispatchQueue
    private let onEvents: @Sendable ([CodexSessionLogEvent]) -> Void
    private let onInvalidated: @Sendable () -> Void
    private let parser = CodexHookEventParser()
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private var partialLine = Data()

    init(
        fileURL: URL,
        queue: DispatchQueue,
        onEvents: @escaping @Sendable ([CodexSessionLogEvent]) -> Void,
        onInvalidated: @escaping @Sendable () -> Void
    ) {
        self.fileURL = fileURL
        self.queue = queue
        self.onEvents = onEvents
        self.onInvalidated = onInvalidated
    }

    deinit { stop() }

    func start() throws {
        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { throw TaskActivityStoreError.openFailed(fileURL.path) }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.handle(source.data) }
        source.setCancelHandler { close(descriptor) }
        lock.withLock { self.source = source }
        source.resume()
        queue.async { [weak self] in self?.readAvailable() }
    }

    func stop() {
        let source = lock.withLock { () -> DispatchSourceFileSystemObject? in
            let source = self.source
            self.source = nil
            return source
        }
        source?.cancel()
    }

    private func handle(_ event: DispatchSource.FileSystemEvent) {
        if event.contains(.rename) || event.contains(.delete) {
            onInvalidated()
            stop()
        } else {
            readAvailable()
        }
    }

    private func readAvailable() {
        guard lock.withLock({ source != nil }),
              let handle = try? FileHandle(forReadingFrom: fileURL)
        else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0; partialLine.removeAll() }
        try? handle.seek(toOffset: offset)
        if let data = try? handle.readToEnd() { partialLine.append(data) }
        offset = size
        var events: [CodexSessionLogEvent] = []
        var start = partialLine.startIndex
        while let newline = partialLine[start...].firstIndex(of: 0x0A) {
            events.append(contentsOf: parser.parseLine(Data(partialLine[start..<newline])))
            start = partialLine.index(after: newline)
        }
        if start > partialLine.startIndex { partialLine.removeSubrange(partialLine.startIndex..<start) }
        if !events.isEmpty { onEvents(events) }
    }
}
