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
    private var stores: [URL: TaskActivityStore] = [:]
    private var watchers: [URL: CodexSessionLogFileWatcher] = [:]
    private var directoryWatchers: [URL: CodexSessionLogDirectoryWatcher] = [:]
    private var hookEventWatcher: CodexHookEventWatcher?
    private var isRunning = false

    public var onChange: (() -> Void)?
    public var onError: ((Error) -> Void)?

    public init(
        catalog: CodexSessionLogCatalog = CodexSessionLogCatalog(),
        databaseURL: URL = TaskMonitorCoordinator.defaultDatabaseURL,
        hookEventURL: URL? = nil,
        watcherQueue: DispatchQueue = DispatchQueue(
            label: "codex-pace-bar.task-monitor",
            qos: .utility
        )
    ) throws {
        self.catalog = catalog
        self.databaseURL = databaseURL
        self.watcherQueue = watcherQueue
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
    }

    public func start() throws {
        guard !isRunning else {
            return
        }
        isRunning = true
        do {
            try rescan()
            try startHookEventWatcher()
        } catch {
            isRunning = false
            throw error
        }
    }

    public func rescan() throws {
        guard isRunning else {
            return
        }
        let files = try catalog.recentLogFiles()
        let desiredFiles = Set(files)
        for fileURL in Array(watchers.keys) where !desiredFiles.contains(fileURL) {
            detach(fileURL: fileURL)
        }
        for fileURL in files {
            try attach(fileURL: fileURL)
        }
        try synchronizeDirectoryWatchers(for: files)
    }

    public func stop() {
        isRunning = false
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

    public func checkIns(since date: Date) async throws -> [CodexDailyWorkCheckIn] {
        try await queryStore.checkIns(since: date)
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
