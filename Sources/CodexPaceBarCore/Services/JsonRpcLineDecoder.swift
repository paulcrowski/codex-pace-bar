import Foundation

public struct JsonRpcDecodingError: Error, Equatable, Sendable {
    public let line: String
    public let message: String

    public init(line: String, message: String) {
        self.line = line
        self.message = message
    }
}

public struct JsonRpcLineDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [Result<JSONValue, JsonRpcDecodingError>] {
        buffer.append(data)

        var results: [Result<JSONValue, JsonRpcDecodingError>] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else {
                continue
            }

            guard let line = String(data: lineData, encoding: .utf8) else {
                results.append(.failure(JsonRpcDecodingError(line: "", message: "Invalid UTF-8.")))
                continue
            }

            do {
                results.append(.success(try JSONValue.parse(line: line)))
            } catch {
                results.append(.failure(JsonRpcDecodingError(line: line, message: error.localizedDescription)))
            }
        }

        return results
    }
}
