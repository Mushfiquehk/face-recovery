import Foundation

/// A minimal encodable JSON tree. The scoring request mixes strings, numbers, booleans and a
/// nested JSON Schema, which no single Codable struct expresses cleanly; this keeps the request
/// builder type-checked rather than stringly-typed.
indirect enum JSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }
}
