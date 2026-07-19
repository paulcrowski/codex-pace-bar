import CodexPaceBarAppSupport
import Foundation
import Testing

struct CodexHookInstallerTests {
    @Test
    func installsWithoutRemovingExistingHooksAndUninstallsOnlyItsOwn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("hooks.json")
        let eventFile = directory.appendingPathComponent("events.jsonl")
        let forwarder = directory.appendingPathComponent("CodexPaceBarHookForwarder")
        try Data("{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"existing-tool\"}]}]}}".utf8).write(to: config)
        let installer = CodexHookInstaller(configurationURL: config, eventFileURL: eventFile)

        try installer.install(forwarderURL: forwarder)
        #expect(installer.isInstalled(forwarderURL: forwarder))
        var status = installer.setupStatus(forwarderURL: forwarder)
        #expect(status.isConfigured)
        #expect(!status.isReceivingEvents)
        #expect(status.observedHookNames.isEmpty)
        #expect(status.displayState(for: "PermissionRequest") == .installed)
        #expect(status.displayState(for: "UserPromptSubmit") == .installed)
        #expect(status.displayState(for: "Stop") == .installed)
        #expect(status.displayState(for: "Unknown") == .notInstalled)
        let installed = String(decoding: try Data(contentsOf: config), as: UTF8.self)
        #expect(installed.contains("existing-tool"))
        #expect(!installed.contains("prompt"))

        try Data(
            """
            {"hook_event_name":"UserPromptSubmit"}
            {"hook_event_name":"Stop"}

            """.utf8
        ).write(to: eventFile)
        status = installer.setupStatus(forwarderURL: forwarder)
        #expect(status.isReceivingEvents)
        #expect(status.observedHookNames == ["UserPromptSubmit", "Stop"])
        #expect(!status.hasObservedAllRequiredHooks)
        #expect(status.displayState(for: "PermissionRequest") == .installed)
        #expect(status.displayState(for: "UserPromptSubmit") == .working)
        #expect(status.displayState(for: "Stop") == .working)

        try installer.uninstall()
        let uninstalled = String(decoding: try Data(contentsOf: config), as: UTF8.self)
        #expect(uninstalled.contains("existing-tool"))
        #expect(!uninstalled.contains(CodexHookInstaller.marker))
    }

    @Test
    func refusesToOverwriteInvalidConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("hooks.json")
        try Data("not json".utf8).write(to: config)
        let installer = CodexHookInstaller(configurationURL: config, eventFileURL: directory.appendingPathComponent("events"))
        #expect(throws: CodexHookInstallerError.invalidConfiguration) {
            try installer.install(forwarderURL: directory.appendingPathComponent("forwarder"))
        }
        #expect(String(decoding: try Data(contentsOf: config), as: UTF8.self) == "not json")
    }
}
