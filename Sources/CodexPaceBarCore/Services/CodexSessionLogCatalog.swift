import Foundation

public struct CodexSessionLogCatalog: Sendable {
    public static let defaultMaximumAge: TimeInterval = 30 * 24 * 60 * 60
    public static let defaultFileLimit = 12

    public let rootURL: URL

    public init(rootURL: URL = Self.defaultRootURL) {
        self.rootURL = rootURL
    }

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func sessionID(for fileURL: URL) -> String? {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem.count >= 36 else {
            return nil
        }
        let candidate = String(stem.suffix(36))
        guard UUID(uuidString: candidate) != nil else {
            return nil
        }
        return candidate.lowercased()
    }

    public func recentLogFiles(
        limit: Int = Self.defaultFileLimit,
        now: Date = Date(),
        maximumAge: TimeInterval = Self.defaultMaximumAge
    ) throws -> [URL] {
        guard limit > 0 else {
            return []
        }

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maximumAge)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var files: [(url: URL, modifiedAt: Date)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else {
                continue
            }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff
            else {
                continue
            }
            files.append((url, modifiedAt))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
    }
}
