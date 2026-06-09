import Foundation

public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var doubleValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    public var intValue: Int? {
        guard let doubleValue, doubleValue.isFinite else {
            return nil
        }
        return Int(doubleValue)
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public static func parse(line: String) throws -> JSONValue {
        guard let data = line.data(using: .utf8) else {
            throw PaceError.jsonDecodingFailed("Line was not valid UTF-8.")
        }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> JSONValue {
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            return try fromAny(object)
        } catch let error as PaceError {
            throw error
        } catch {
            throw PaceError.jsonDecodingFailed(error.localizedDescription)
        }
    }

    public static func fromAny(_ value: Any) throws -> JSONValue {
        switch value {
        case _ as NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let bool as Bool:
            return .bool(bool)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(try array.map(fromAny))
        case let object as [String: Any]:
            return .object(try object.mapValues(fromAny))
        default:
            throw PaceError.jsonDecodingFailed("Unsupported JSON value \(type(of: value)).")
        }
    }

    public func anyValue() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { $0.anyValue() }
        case let .object(values):
            return values.mapValues { $0.anyValue() }
        }
    }
}
