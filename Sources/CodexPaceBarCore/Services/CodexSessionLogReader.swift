import Foundation

public struct CodexSessionLogReader: Sendable {
    private static let checkpointSize = 256
    public static let defaultInitialReadLimitBytes: UInt64 = 2 * 1_024 * 1_024

    private let parser: CodexSessionLogParser
    private let initialReadLimitBytes: UInt64
    private var offset: UInt64 = 0
    private var partialLine = Data()
    private var checkpoint = Data()

    public init(
        parser: CodexSessionLogParser = CodexSessionLogParser(),
        initialReadLimitBytes: UInt64 = Self.defaultInitialReadLimitBytes
    ) {
        self.parser = parser
        self.initialReadLimitBytes = initialReadLimitBytes
    }

    public mutating func readNewEvents(from fileURL: URL) throws -> [CodexSessionLogEvent] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        if fileSize < offset {
            reset()
        } else if offset > 0, !checkpoint.isEmpty {
            let currentCheckpoint = try readCheckpoint(
                from: handle,
                offset: offset
            )
            if currentCheckpoint != checkpoint {
                reset()
            }
        }

        let readStart: UInt64
        let startsInsideExistingLine: Bool
        if offset == 0, initialReadLimitBytes > 0, fileSize > initialReadLimitBytes {
            readStart = fileSize - initialReadLimitBytes
            startsInsideExistingLine = true
        } else {
            readStart = offset
            startsInsideExistingLine = false
        }

        try handle.seek(toOffset: readStart)
        if var data = try handle.readToEnd(), !data.isEmpty {
            if startsInsideExistingLine {
                if let newline = data.firstIndex(of: 0x0A) {
                    data.removeSubrange(data.startIndex...newline)
                } else {
                    data.removeAll(keepingCapacity: false)
                }
            }
            partialLine.append(data)
        }
        offset = fileSize
        checkpoint = try readCheckpoint(
            from: handle,
            offset: fileSize
        )

        var events: [CodexSessionLogEvent] = []
        var lineStart = partialLine.startIndex
        while let newline = partialLine[lineStart...].firstIndex(of: 0x0A) {
            if let event = parser.parseLine(Data(partialLine[lineStart..<newline])) {
                events.append(event)
            }
            lineStart = partialLine.index(after: newline)
        }
        if lineStart > partialLine.startIndex {
            partialLine.removeSubrange(partialLine.startIndex..<lineStart)
        }
        return events
    }

    private mutating func reset() {
        offset = 0
        partialLine.removeAll(keepingCapacity: true)
        checkpoint.removeAll(keepingCapacity: true)
    }

    private func readCheckpoint(
        from handle: FileHandle,
        offset: UInt64
    ) throws -> Data {
        guard offset > 0 else {
            return Data()
        }

        let start = offset > UInt64(Self.checkpointSize)
            ? offset - UInt64(Self.checkpointSize)
            : 0
        try handle.seek(toOffset: start)
        return try handle.read(upToCount: Int(offset - start)) ?? Data()
    }
}
