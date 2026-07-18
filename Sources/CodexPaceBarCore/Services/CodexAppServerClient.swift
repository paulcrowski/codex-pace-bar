import Foundation

public struct CodexAppServerNotification: Equatable, Sendable {
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.method = method
        self.params = params
    }
}

public actor CodexAppServerClient: CodexAppServerRequesting {
    private let executableURL: URL
    private var process: Process?
    private var processGeneration: UUID?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var decoder = JsonRpcLineDecoder()
    private var initialized = false
    private var initializationTask: Task<Void, Error>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var notificationContinuations: [UUID: AsyncStream<CodexAppServerNotification>.Continuation] = [:]

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public func ensureInitialized() async throws {
        if initialized, process?.isRunning == true {
            return
        }

        if let initializationTask {
            try await initializationTask.value
            return
        }

        try startIfNeeded()

        let task = Task { [self] in
            _ = try await sendRequest(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codex_pace_bar"),
                        "title": .string("Codex Pace Bar"),
                        "version": .string(Self.clientVersion)
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true)
                    ])
                ]),
                timeoutSeconds: 10
            )

            try writeNotification(method: "initialized", params: .object([:]))
        }
        initializationTask = task

        do {
            try await task.value
            initialized = true
            initializationTask = nil
        } catch {
            await shutdown()
            throw error
        }
    }

    public func request(method: String, params: JSONValue? = nil, timeoutSeconds: TimeInterval = 10) async throws -> JSONValue {
        try await ensureInitialized()
        return try await sendRequest(method: method, params: params, timeoutSeconds: timeoutSeconds)
    }

    public func notifications() -> AsyncStream<CodexAppServerNotification> {
        let subscriberID = UUID()
        return AsyncStream { continuation in
            notificationContinuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeNotificationSubscriber(subscriberID) }
            }
        }
    }

    public func shutdown() async {
        initializationTask?.cancel()
        initializationTask = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        processGeneration = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        initialized = false
        initializationTask = nil
        failPending(PaceError.appServerExited(nil))
        finishNotificationStreams()
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

        initialized = false
        decoder = JsonRpcLineDecoder()

        let process = Process()
        let generation = UUID()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { await self?.receive(data) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(
                    status: process.terminationStatus,
                    generation: generation
                )
            }
        }

        self.processGeneration = generation

        do {
            try process.run()
        } catch {
            throw PaceError.appServerStartupFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    private func sendRequest(method: String, params: JSONValue?, timeoutSeconds: TimeInterval) async throws -> JSONValue {
        let id = nextRequestID
        nextRequestID += 1

        return try await withTimeout(seconds: timeoutSeconds, operationName: method) { [self] in
            try await performRequest(id: id, method: method, params: params)
        }
    }

    private func performRequest(id: Int, method: String, params: JSONValue?) async throws -> JSONValue {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(isolation: self) { continuation in
                pending[id] = continuation
                do {
                    try writeRequest(id: id, method: method, params: params)
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelPendingRequest(id) }
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operationName: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PaceError.appServerTimeout(operationName)
            }

            guard let result = try await group.next() else {
                throw PaceError.appServerTimeout(operationName)
            }
            group.cancelAll()
            return result
        }
    }

    private func writeRequest(id: Int, method: String, params: JSONValue?) throws {
        var message: [String: Any] = [
            "id": id,
            "method": method
        ]

        if let params {
            message["params"] = params.anyValue()
        }

        try write(message: message)
    }

    private func writeNotification(method: String, params: JSONValue?) throws {
        var message: [String: Any] = [
            "method": method
        ]

        if let params {
            message["params"] = params.anyValue()
        }

        try write(message: message)
    }

    private func write(message: [String: Any]) throws {
        guard let stdinPipe else {
            throw PaceError.appServerWriteFailed
        }

        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message, options: [])
        else {
            throw PaceError.jsonEncodingFailed
        }

        var line = data
        line.append(0x0A)
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            throw PaceError.appServerWriteFailed
        }
    }

    private func receive(_ data: Data) {
        let results = decoder.append(data)
        for result in results {
            switch result {
            case let .success(message):
                handle(message)
            case let .failure(error):
                failPending(PaceError.jsonDecodingFailed(error.message))
            }
        }
    }

    private func handle(_ message: JSONValue) {
        guard let object = message.objectValue else {
            return
        }

        if let method = object["method"]?.stringValue {
            let notification = CodexAppServerNotification(
                method: method,
                params: object["params"]
            )
            for continuation in notificationContinuations.values {
                continuation.yield(notification)
            }
            return
        }

        guard let id = object["id"]?.intValue else {
            return
        }

        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }

        if let error = object["error"]?.objectValue {
            let code = error["code"]?.intValue
            let message = error["message"]?.stringValue ?? "Unknown error"
            continuation.resume(throwing: PaceError.jsonRpcError(code: code, message: message))
            return
        }

        continuation.resume(returning: object["result"] ?? .null)
    }

    private func handleTermination(status: Int32, generation: UUID) {
        guard processGeneration == generation else {
            return
        }

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        processGeneration = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        initialized = false
        failPending(PaceError.appServerExited(status))
        finishNotificationStreams()
    }

    private func cancelPendingRequest(_ id: Int) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func failPending(_ error: Error) {
        let pending = self.pending
        self.pending.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    private func removeNotificationSubscriber(_ id: UUID) {
        notificationContinuations.removeValue(forKey: id)
    }

    private func finishNotificationStreams() {
        let continuations = notificationContinuations.values
        notificationContinuations.removeAll()
        for continuation in continuations {
            continuation.finish()
        }
    }

    private static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
