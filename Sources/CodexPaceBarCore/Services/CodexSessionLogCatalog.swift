import Foundation

public struct CodexSessionLogCatalog: Sendable {
    public static let defaultMaximumAge: TimeInterval = 30 * 24 * 60 * 60
    public static let defaultFileLimit = 12
    public static let defaultMaximumFileSize: UInt64 = 2 * 1_024 * 1_024

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
        maximumAge: TimeInterval = Self.defaultMaximumAge,
        maximumFileSize: UInt64 = Self.defaultMaximumFileSize
    ) throws -> [URL] {
        guard limit > 0 else {
            return []
        }

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maximumAge)
        var files: [(url: URL, modifiedAt: Date)] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        for directory in candidateDirectories(now: now, maximumAge: maximumAge) {
            let children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            for url in children {
                guard url.pathExtension == "jsonl" else { continue }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff,
                      UInt64(values.fileSize ?? 0) <= maximumFileSize
                else { continue }
                files.append((url, modifiedAt))
            }
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
    }

    private func candidateDirectories(now: Date, maximumAge: TimeInterval) -> [URL] {
        let fileManager = FileManager.default
        var directories: [URL] = [rootURL]
        let calendar = Calendar(identifier: .gregorian)
        let dayCount = max(0, Int(ceil(maximumAge / (24 * 60 * 60))))
        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = components.year, let month = components.month, let dayValue = components.day else { continue }
            let directory = rootURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", dayValue), isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) {
                directories.append(directory)
            }
        }
        return Array(Set(directories))
    }
}
