import Foundation

/// The decoded body of one Scoring Run, before it becomes SwiftData models.
struct ScoringResponse: Decodable {
    struct Quality: Decodable {
        let lighting: Int
        let sharpness: Int
        let faceFullyVisible: Bool
        let usable: Bool
    }

    let underEyeDarkness: Int
    let underEyePuffiness: Int
    let facialPuffiness: Int
    let eyeRedness: Int
    let skinDullness: Int
    let holisticTiredness: Int
    let captureQuality: Quality

    /// The schema constrains these to 0-100, but `strict` is enforced by the provider and
    /// ADR 0001 exists because providers differ. Clamping here keeps a misbehaving provider
    /// from poisoning baseline arithmetic.
    private static func clamped(_ value: Int) -> Int { min(100, max(0, value)) }

    func makeSignalSet() -> SignalSet {
        SignalSet(
            underEyeDarkness: Self.clamped(underEyeDarkness),
            underEyePuffiness: Self.clamped(underEyePuffiness),
            facialPuffiness: Self.clamped(facialPuffiness),
            eyeRedness: Self.clamped(eyeRedness),
            skinDullness: Self.clamped(skinDullness),
            holisticTiredness: Self.clamped(holisticTiredness)
        )
    }

    func makeCaptureQuality() -> CaptureQuality {
        CaptureQuality(
            lighting: Self.clamped(captureQuality.lighting),
            sharpness: Self.clamped(captureQuality.sharpness),
            faceFullyVisible: captureQuality.faceFullyVisible,
            isUsable: captureQuality.usable
        )
    }
}

enum ScoringError: LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case providerUnavailable(String)
    case providerRejected(status: Int, detail: String)
    case noRoute(String)
    case http(status: Int, body: String)
    case emptyResponse
    case malformedResponse(underlying: String, body: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No OpenRouter API key. Add one in Settings."
        case .imageEncodingFailed:
            "The photo could not be prepared for scoring."
        case .providerUnavailable(let detail):
            "\(ScoringConfiguration.provider) is unavailable, and fallbacks are pinned off so the scan was not rerouted. \(detail)"
        case .providerRejected(let status, let detail):
            "\(ScoringConfiguration.provider) rejected the request (\(status)). \(detail.prefix(500))"
        case .noRoute(let detail):
            "OpenRouter would not route to \(ScoringConfiguration.provider). Check your OpenRouter privacy and provider settings. \(detail)"
        case .http(let status, let body):
            "OpenRouter returned \(status). \(body.prefix(300))"
        case .emptyResponse:
            "The model returned no content."
        case .malformedResponse(let underlying, _):
            "The model's response did not match the expected schema. \(underlying)"
        case .transport(let detail):
            "Could not reach OpenRouter. \(detail)"
        }
    }

    /// Worth an automatic retry: the provider is busy or briefly down, and the same request may
    /// well succeed a few seconds later.
    var isTransient: Bool {
        switch self {
        case .providerUnavailable, .transport: true
        case .providerRejected(let status, _), .http(let status, _): status == 429 || status >= 500
        default: false
        }
    }

    /// What to tell the user. `errorDescription` has the technical detail; this says what it
    /// means and what to do, in plain words.
    var friendlyDescription: String {
        switch self {
        case .missingAPIKey:
            "The app needs its connection key before it can read your photo. Open Settings to add it."
        case .imageEncodingFailed:
            "Something went wrong preparing your photo."
        case .providerUnavailable, .providerRejected(429, _), .providerRejected(500..., _),
             .http(429, _), .http(500..., _):
            "The scoring service is busy right now. This usually passes within a minute."
        case .transport:
            "The app could not reach the internet. Check your connection."
        case .noRoute, .providerRejected, .http:
            "The scoring service did not accept the photo."
        case .emptyResponse, .malformedResponse:
            "The scoring service gave an answer the app could not read."
        }
    }

    /// Every failure here is worth retrying by hand; none of them should silently drop a scan.
    var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .imageEncodingFailed: false
        default: true
        }
    }
}
