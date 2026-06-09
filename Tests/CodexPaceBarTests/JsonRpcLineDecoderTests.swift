import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct JsonRpcLineDecoderTests {
    @Test
    func decodesCompleteAndPartialLines() throws {
        var decoder = JsonRpcLineDecoder()

        #expect(decoder.append(Data("{\"id\":1".utf8)).isEmpty)
        let results = decoder.append(Data(",\"result\":{\"ok\":true}}\n{\"method\":\"note\"}\n".utf8))

        #expect(results.count == 2)

        let first = try results[0].get()
        #expect(first["id"]?.intValue == 1)
        #expect(first["result"]?["ok"] == .bool(true))

        let second = try results[1].get()
        #expect(second["method"]?.stringValue == "note")
    }

    @Test
    func invalidJsonReturnsFailureWithoutCrashing() {
        var decoder = JsonRpcLineDecoder()

        let results = decoder.append(Data("not json\n".utf8))

        #expect(results.count == 1)
        if case .failure = results[0] {
            return
        }
        Issue.record("Expected invalid JSON to return a failure result.")
    }

    @Test
    func responseIdCorrelationFieldsAreReadable() throws {
        let message = try JSONValue.parse(line: "{\"id\":42,\"result\":{\"rateLimits\":null}}\n")

        #expect(message["id"]?.intValue == 42)
        #expect(message["result"]?["rateLimits"] == .null)
    }
}
