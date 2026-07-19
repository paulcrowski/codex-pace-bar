import Darwin
import Foundation

public final class CodexSessionLogDirectoryWatcher: @unchecked Sendable {
    public static let changeDebounceInterval: TimeInterval = 0.1

    public typealias ChangeHandler = @Sendable () -> Void

    private let directoryURL: URL
    private let queue: DispatchQueue
    private let onChange: ChangeHandler
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var isActive = false
    private var changeNotificationPending = false

    public init(
        directoryURL: URL,
        queue: DispatchQueue = DispatchQueue(label: "codex-pace-bar.session-catalog"),
        onChange: @escaping ChangeHandler
    ) {
        self.directoryURL = directoryURL
        self.queue = queue
        self.onChange = onChange
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

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CodexSessionLogDirectoryWatcherError.openFailed(directoryURL.path)
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
        lock.lock()
        let active = isActive
        let shouldSchedule = active && !changeNotificationPending
        if shouldSchedule {
            changeNotificationPending = true
        }
        lock.unlock()
        guard shouldSchedule else {
            return
        }

        queue.asyncAfter(deadline: .now() + Self.changeDebounceInterval) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let active = self.isActive
            self.changeNotificationPending = false
            self.lock.unlock()
            guard active else { return }
            self.onChange()
        }
    }
}

public enum CodexSessionLogDirectoryWatcherError: Error, Equatable, Sendable {
    case openFailed(String)
}
