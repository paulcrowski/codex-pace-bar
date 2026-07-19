import Foundation

public struct CodexHookInstaller: Sendable {
    public static let marker = "CodexPaceBarHookForwarder"
    public static let requiredHookNames: Set<String> = [
        "PermissionRequest", "UserPromptSubmit", "Stop"
    ]
    public let configurationURL: URL
    public let eventFileURL: URL

    public init(
        configurationURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json"),
        eventFileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("task-hook-events.jsonl")
    ) {
        self.configurationURL = configurationURL
        self.eventFileURL = eventFileURL
    }

    public func install(forwarderURL: URL) throws {
        let snapshot = try loadConfigurationSnapshot()
        var root = snapshot.root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.requiredHookNames.sorted() {
            var groups = cleanedGroups(hooks[event])
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": "\(shellQuote(forwarderURL.path)) --event-file \(shellQuote(eventFileURL.path))",
                    "timeout": 2
                ]]
            ])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try write(root, expectedData: snapshot.data)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return }
        let snapshot = try loadConfigurationSnapshot()
        var root = snapshot.root
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            let groups = cleanedGroups(hooks[key])
            if groups.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = groups }
        }
        root["hooks"] = hooks
        try write(root, expectedData: snapshot.data)
    }

    public func isInstalled(forwarderURL: URL) -> Bool {
        setupStatus(forwarderURL: forwarderURL).isConfigured
    }

    public func setupStatus(forwarderURL: URL) -> CodexHookSetupStatus {
        let expected = forwarderURL.path
        let installedHookNames: Set<String>
        if let root = try? loadConfiguration(),
           let hooks = root["hooks"] as? [String: Any] {
            installedHookNames = Set(Self.requiredHookNames.filter { eventName in
                groups(from: hooks[eventName]).contains { group in
                    handlers(from: group).contains { handler in
                        (handler["command"] as? String)?.contains(expected) == true
                    }
                }
            })
        } else {
            installedHookNames = []
        }

        var observedHookNames: Set<String> = []
        if let data = try? boundedTailData(at: eventFileURL, maximumBytes: 2 * 1_024 * 1_024) {
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let eventName = object["hook_event_name"] as? String,
                      Self.requiredHookNames.contains(eventName)
                else { continue }
                observedHookNames.insert(eventName)
            }
        }

        return CodexHookSetupStatus(
            installedHookNames: installedHookNames,
            observedHookNames: observedHookNames
        )
    }

    private func loadConfiguration() throws -> [String: Any] {
        try loadConfigurationSnapshot().root
    }

    private func loadConfigurationSnapshot() throws -> ConfigurationSnapshot {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return ConfigurationSnapshot(root: [:], data: nil)
        }
        let data = try Data(contentsOf: configurationURL)
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any]
        else {
            throw CodexHookInstallerError.invalidConfiguration
        }
        return ConfigurationSnapshot(root: object, data: data)
    }

    private func cleanedGroups(_ value: Any?) -> [[String: Any]] {
        groups(from: value).compactMap { group in
            var group = group
            let remaining = handlers(from: group).filter { handler in
                guard let command = handler["command"] as? String else { return true }
                return !command.contains(Self.marker)
            }
            guard !remaining.isEmpty else { return nil }
            group["hooks"] = remaining
            return group
        }
    }

    private func groups(from value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private func handlers(from group: [String: Any]) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func write(_ object: [String: Any], expectedData: Data?) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let currentData = FileManager.default.fileExists(atPath: configurationURL.path)
            ? try Data(contentsOf: configurationURL)
            : nil
        guard currentData == expectedData else {
            throw CodexHookInstallerError.configurationChanged
        }
        if let currentData {
            let backupURL = configurationURL.appendingPathExtension("codex-pace-bar-backup")
            try currentData.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configurationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func boundedTailData(at url: URL, maximumBytes: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > maximumBytes ? size - maximumBytes : 0
        try handle.seek(toOffset: start)
        var data = try handle.readToEnd() ?? Data()
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }
        return data
    }

    private struct ConfigurationSnapshot {
        let root: [String: Any]
        let data: Data?
    }
}

public struct CodexHookSetupStatus: Equatable, Sendable {
    public let installedHookNames: Set<String>
    public let observedHookNames: Set<String>

    public init(installedHookNames: Set<String>, observedHookNames: Set<String>) {
        self.installedHookNames = installedHookNames
        self.observedHookNames = observedHookNames
    }

    public static let notConfigured = CodexHookSetupStatus(
        installedHookNames: [],
        observedHookNames: []
    )

    public var isConfigured: Bool {
        installedHookNames.isSuperset(of: CodexHookInstaller.requiredHookNames)
    }

    public var isReceivingEvents: Bool {
        !observedHookNames.isEmpty
    }

    public var hasObservedAllRequiredHooks: Bool {
        observedHookNames.isSuperset(of: CodexHookInstaller.requiredHookNames)
    }

    public func displayState(for hookName: String) -> CodexHookDisplayState {
        if observedHookNames.contains(hookName) { return .working }
        if installedHookNames.contains(hookName) { return .installed }
        return .notInstalled
    }
}

public enum CodexHookDisplayState: Equatable, Sendable {
    case notInstalled
    case installed
    case working
}

public enum CodexHookInstallerError: Error, Equatable, Sendable {
    case invalidConfiguration
    case configurationChanged
}
