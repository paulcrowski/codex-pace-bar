import Foundation

public struct CodexHookInstaller: Sendable {
    public static let marker = "CodexPaceBarHookForwarder"
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
        var root = try loadConfiguration()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ["UserPromptSubmit", "PermissionRequest", "Stop"] {
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
        try write(root)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return }
        var root = try loadConfiguration()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            let groups = cleanedGroups(hooks[key])
            if groups.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = groups }
        }
        root["hooks"] = hooks
        try write(root)
    }

    public func isInstalled(forwarderURL: URL) -> Bool {
        guard let root = try? loadConfiguration(),
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        let expected = forwarderURL.path
        return hooks.values.contains { value in
            groups(from: value).contains { group in
                handlers(from: group).contains { handler in
                    (handler["command"] as? String)?.contains(expected) == true
                }
            }
        }
    }

    private func loadConfiguration() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [:] }
        let data = try Data(contentsOf: configurationURL)
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any] else {
            throw CodexHookInstallerError.invalidConfiguration
        }
        return object
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

    private func write(_ object: [String: Any]) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configurationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum CodexHookInstallerError: Error, Equatable, Sendable {
    case invalidConfiguration
}
