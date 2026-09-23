import Foundation

/// Talks to OpenRouter directly from the device. There is no backend and the key lives in the
/// Keychain (ADR 0003).
struct OpenRouterClient {
    var apiKey: String
    var session: URLSession = .shared

    /// What came back from one call, including the verbatim body for the Scoring Run.
    struct Completion {
        let response: ScoringResponse
        /// The full response body as returned, stored so a later schema change can re-parse
        /// this scan without re-scoring it.
        let rawJSON: String
        /// The provider OpenRouter reports actually served the request. Should always equal
        /// the pinned provider; recorded rather than assumed.
        let servedBy: String
    }

    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        struct Failure: Decodable { let message: String?; let code: JSONCode? }
        /// OpenRouter returns `code` as either a number or a string depending on the path.
        enum JSONCode: Decodable {
            case int(Int), string(String)
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(Int.self) { self = .int(value) }
                else { self = .string(try container.decode(String.self)) }
            }
            var description: String {
                switch self {
                case .int(let value): String(value)
                case .string(let value): value
                }
            }
        }
        let choices: [Choice]?
        let provider: String?
        let error: Failure?
    }

    func score(imageData: Data) async throws -> Completion {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScoringError.missingAPIKey
        }

        var request = URLRequest(url: ScoringConfiguration.baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Face Recovery", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body(imageData: imageData))
        request.timeoutInterval = 120

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw ScoringError.transport(error.localizedDescription)
        }

        let rawJSON = String(data: data, encoding: .utf8) ?? ""
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)

        if let failure = envelope?.error {
            let detail = failure.message ?? "No detail given."
            let code = failure.code.flatMap { Int($0.description) } ?? status
            // "Provider returned error" is OpenRouter's wrapper for a rejection by the pinned provider
            // itself; the real reason is only in `error.metadata.raw`.
            if let raw = Self.upstreamRaw(in: data) {
                throw ScoringError.providerRejected(status: code, detail: raw)
            }
            // Fallbacks are pinned off, so a routing refusal usually means account settings
            // (privacy, provider ignore list) exclude the pinned provider (ADR 0001).
            if detail.localizedCaseInsensitiveContains("no allowed providers")
                || detail.localizedCaseInsensitiveContains("no endpoints found") {
                throw ScoringError.noRoute(detail)
            }
            if code == 502 || code == 503 {
                throw ScoringError.providerUnavailable(detail)
            }
            throw ScoringError.http(status: code == 0 ? 502 : code, body: detail)
        }

        guard (200..<300).contains(status) else {
            throw ScoringError.http(status: status, body: rawJSON)
        }

        guard let content = envelope?.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScoringError.emptyResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let parsed = try decoder.decode(ScoringResponse.self, from: Data(content.utf8))
            return Completion(
                response: parsed,
                rawJSON: rawJSON,
                servedBy: envelope?.provider ?? ScoringConfiguration.provider
            )
        } catch {
            throw ScoringError.malformedResponse(underlying: String(describing: error), body: content)
        }
    }

    /// `error.metadata.raw` is the upstream provider's own error, as a string or an object
    /// depending on the provider, so it is read untyped rather than through `Envelope`.
    private static func upstreamRaw(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let metadata = error["metadata"] as? [String: Any],
              let raw = metadata["raw"] else { return nil }
        if let text = raw as? String { return text.isEmpty ? nil : text }
        guard let encoded = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    /// A cheap request used by Settings to prove the key works before a real scan.
    func testConnection() async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScoringError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw ScoringError.transport(error.localizedDescription)
        }
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ScoringError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func body(imageData: Data) -> JSONValue {
        let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        return .object([
            "model": .string(ScoringConfiguration.modelId),
            "provider": .object([
                "order": .array([.string(ScoringConfiguration.provider)]),
                "allow_fallbacks": .bool(false),
            ]),
            "seed": .int(ScoringConfiguration.seed),
            "temperature": .int(ScoringConfiguration.temperature),
            "response_format": ScoringSchema.responseFormat,
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object(["type": .string("text"), "text": .string(ScoringPrompt.text)]),
                        .object([
                            "type": .string("image_url"),
                            "image_url": .object(["url": .string(dataURL)]),
                        ]),
                    ]),
                ])
            ]),
        ])
    }
}
