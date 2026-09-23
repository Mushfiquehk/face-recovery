import Foundation

/// Everything that determines how a Face Scan is scored, pinned in one place and recorded on
/// every Scoring Run. Changing any of these is a breaking change to the dataset (ADR 0001):
/// bump the matching version and never apply it retroactively to stored scans.
enum ScoringConfiguration {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    static let modelId = "z-ai/glm-5.3-flash"

    /// Pinned with fallbacks disabled: 32 providers serve this model and they do not agree on
    /// `seed` or `structured_outputs` support. An outage must fail the scan, not reroute it.
    static let provider = "CoreWeave"

    static let seed = 42
    static let temperature = 0

    static let promptVersion = ScoringPrompt.version
    static let schemaVersion = ScoringSchema.version

    /// Images are downscaled before upload. At roughly $0.0005 per scan the cost is
    /// immaterial; this is about upload time on cellular.
    static let imageLongEdge: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.8

    /// Mirrors the `SCORING_*` values in `.env.example`, which the Python pipeline must match
    /// or re-scored Signals will not be comparable.
    static var provenanceSummary: [(label: String, value: String)] {
        [
            ("Model", modelId),
            ("Provider", provider),
            ("Seed", String(seed)),
            ("Prompt version", promptVersion),
            ("Schema version", schemaVersion),
        ]
    }
}
