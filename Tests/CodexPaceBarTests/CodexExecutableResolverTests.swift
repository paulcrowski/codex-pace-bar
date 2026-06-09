import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct CodexExecutableResolverTests {
    @Test
    func resolvesConfiguredPath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("bin/codex")
        try makeExecutable(at: executable)

        let resolver = CodexExecutableResolver(pathEnvironment: "", homeDirectory: root, systemCandidates: [])

        #expect(try resolver.resolve(configuredPath: executable.path).standardizedFileURL == executable.standardizedFileURL)
    }

    @Test
    func resolvesFromPathEnvironment() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("custom-bin")
        let executable = bin.appendingPathComponent("codex")
        try makeExecutable(at: executable)

        let resolver = CodexExecutableResolver(pathEnvironment: bin.path, homeDirectory: root, systemCandidates: [])

        #expect(try resolver.resolve(configuredPath: nil).standardizedFileURL == executable.standardizedFileURL)
    }

    @Test
    func configuredRelativeExecutableDoesNotFallBackToCodex() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("custom-bin")
        try makeExecutable(at: bin.appendingPathComponent("codex"))

        let resolver = CodexExecutableResolver(pathEnvironment: bin.path, homeDirectory: root, systemCandidates: [])

        do {
            _ = try resolver.resolve(configuredPath: "codex-beta")
            Issue.record("Expected codexExecutableNotFound")
        } catch let error as PaceError {
            #expect(error == .codexExecutableNotFound)
        }
    }

    @Test
    func configuredPathDoesNotFallBackToCodex() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("custom-bin")
        try makeExecutable(at: bin.appendingPathComponent("codex"))

        let resolver = CodexExecutableResolver(pathEnvironment: bin.path, homeDirectory: root, systemCandidates: [])

        do {
            _ = try resolver.resolve(configuredPath: root.appendingPathComponent("missing/codex").path)
            Issue.record("Expected codexExecutableNotFound")
        } catch let error as PaceError {
            #expect(error == .codexExecutableNotFound)
        }
    }

    @Test
    func resolvesMiseInstall() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root
            .appendingPathComponent(".local/share/mise/installs/npm-openai-codex/0.138.0/bin/codex")
        try makeExecutable(at: executable)

        let resolver = CodexExecutableResolver(pathEnvironment: "", homeDirectory: root, systemCandidates: [])

        #expect(try resolver.resolve(configuredPath: nil).standardizedFileURL == executable.standardizedFileURL)
    }

    @Test
    func returnsErrorWhenExecutableIsMissing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = CodexExecutableResolver(pathEnvironment: "", homeDirectory: root, systemCandidates: [])

        do {
            _ = try resolver.resolve(configuredPath: nil)
            Issue.record("Expected codexExecutableNotFound")
        } catch let error as PaceError {
            #expect(error == .codexExecutableNotFound)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPaceBarTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
