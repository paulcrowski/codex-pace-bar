import Darwin
import Foundation

public final class CodexSessionLogFileWatcher: @unchecked Sendable {
    public typealias EventHandler = @Sendable ([CodexSessionLogEvent]) -> Void
    public typealias InvalidationHandler = @Sendable () -> Void

    private let fileURL: URL
    private let queue: DispatchQueue
    private let onEvents: EventHandler
    private let onInvalidated: InvalidationHandler
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var reader = CodexSessionLogReader()
    private var isActive = false

    public init(
        fileURL: URL,
        queue: DispatchQueue = DispatchQueue(label: "codex-pace-bar.session-log"),
        onEvents: @escaping EventHandler,
        onInvalidated: @escaping InvalidationHandler = {}
    ) {
        self.fileURL = fileURL
        self.queue = queue
        self.onEvents = onEvents
        self.onInvalidated = onInvalidated
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else {
            return
        }

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CodexSessionLogFileWatcherError.openFailed(fileURL.path)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handle(source.data)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        isActive = true
        source.resume()
        queue.async { [weak self] in
            self?.readAvailableEvents()
        }
    }

    public func stop() {
        lock.lock()
        let source = self.source
        self.source = nil
        isActive = false
        lock.unlock()
        source?.cancel()
    }

    private func handle(_ event: DispatchSource.FileSystemEvent) {
        if event.contains(.rename) || event.contains(.delete) {
            onInvalidated()
            stop()
            return
        }
        readAvailableEvents()
    }

    private func readAvailableEvents() {
        lock.lock()
        let isActive = self.isActive
        lock.unlock()
        guard isActive else {
            return
        }

        do {
            let events = try reader.readNewEvents(from: fileURL)
            lock.lock()
            let isStillActive = self.isActive
            lock.unlock()
            guard isStillActive else {
                return
            }
            guard !events.isEmpty else {
                return
            }
            onEvents(events)
        } catch {
            onInvalidated()
        }
    }
}

public enum CodexSessionLogFileWatcherError: Error, Equatable, Sendable {
    case openFailed(String)
}
