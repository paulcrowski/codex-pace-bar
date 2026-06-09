import Foundation

public struct CodexExecutableResolver {
    public let pathEnvironment: String
    public let homeDirectory: URL
    public let fileManager: FileManager
    public let systemCandidates: [URL]

    public init(
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        systemCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
    ) {
        self.pathEnvironment = pathEnvironment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.systemCandidates = systemCandidates
    }

    public func resolve(configuredPath: String?) throws -> URL {
        if let configuredPath = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty {
            if configuredPath.contains("/") {
                let expanded = expandTilde(configuredPath)
                if isExecutable(expanded) {
                    return expanded
                }
                throw PaceError.codexExecutableNotFound
            } else if configuredPath != "codex" {
                if let resolved = findInPath(configuredPath) {
                    return resolved
                }
                throw PaceError.codexExecutableNotFound
            }
        }

        if let pathResolved = findInPath("codex") {
            return pathResolved
        }

        for candidate in fixedCandidatesBeforeMise() where isExecutable(candidate) {
            return candidate
        }

        if let miseCandidate = findMiseCandidate() {
            return miseCandidate
        }

        for candidate in fixedCandidatesAfterMise() where isExecutable(candidate) {
            return candidate
        }

        throw PaceError.codexExecutableNotFound
    }

    private func findInPath(_ executableName: String) -> URL? {
        for entry in pathEnvironment.split(separator: ":") {
            let directory = String(entry)
            guard !directory.isEmpty else {
                continue
            }

            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName)
            if isExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func fixedCandidatesBeforeMise() -> [URL] {
        systemCandidates + [
            homeDirectory.appendingPathComponent(".local/bin/codex")
        ]
    }

    private func fixedCandidatesAfterMise() -> [URL] {
        [
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent(".bun/bin/codex")
        ]
    }

    private func findMiseCandidate() -> URL? {
        let installs = homeDirectory.appendingPathComponent(".local/share/mise/installs/npm-openai-codex")
        guard let versions = try? fileManager.contentsOfDirectory(at: installs, includingPropertiesForKeys: nil) else {
            return nil
        }

        return versions
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { $0.appendingPathComponent("bin/codex") }
            .first(where: isExecutable)
    }

    private func expandTilde(_ path: String) -> URL {
        if path == "~" {
            return homeDirectory
        }

        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }

        return URL(fileURLWithPath: path)
    }

    private func isExecutable(_ url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }
}
