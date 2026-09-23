import Foundation

/// The JSON Schema the model must fill. Versioned: a change here makes newly scored scans
/// incomparable with old ones, so `version` must be bumped alongside any edit.
enum ScoringSchema {
    static let version = "v1"
    static let name = "face_scan_rating"

    private static func rating(_ description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "minimum": .int(0),
            "maximum": .int(100),
            "description": .string(description),
        ])
    }

    /// Ordered so the schema's own key order matches `Signal.allCases`.
    private static var signalProperties: [String: JSONValue] {
        var properties: [String: JSONValue] = [:]
        for signal in Signal.allCases {
            properties[signal.jsonKey] = rating("\(signal.displayName), 0-100, higher is more pronounced")
        }
        return properties
    }

    static var schema: JSONValue {
        var properties = signalProperties
        properties["holistic_tiredness"] = rating("Overall impression of tiredness, 0-100, higher is more tired")
        properties["capture_quality"] = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "lighting": rating("Adequacy and evenness of lighting, 0-100"),
                "sharpness": rating("Fine detail resolved around eyes and skin, 0-100"),
                "face_fully_visible": .object([
                    "type": .string("boolean"),
                    "description": .string("Whole face including both eyes and the full under-eye area is in frame and unobstructed"),
                ]),
                "usable": .object([
                    "type": .string("boolean"),
                    "description": .string("The ratings can be made with reasonable confidence from this photograph"),
                ]),
            ]),
            "required": .array([
                .string("lighting"), .string("sharpness"),
                .string("face_fully_visible"), .string("usable"),
            ]),
        ])

        var required: [JSONValue] = Signal.allCases.map { .string($0.jsonKey) }
        required.append(.string("holistic_tiredness"))
        required.append(.string("capture_quality"))

        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array(required),
        ])
    }

    static var responseFormat: JSONValue {
        .object([
            "type": .string("json_schema"),
            "json_schema": .object([
                "name": .string(name),
                "strict": .bool(true),
                "schema": schema,
            ]),
        ])
    }
}
