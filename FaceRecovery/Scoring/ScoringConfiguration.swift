import Foundation

/// Everything that determines how a Face Scan is scored, pinned in one place and recorded on
/// every Scoring Run. Changing any of these is a breaking change to the dataset (ADR 0001):
/// bump the matching version and never apply it retroactively to stored scans.
enum ScoringConfiguration {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Free, open-weight multimodal model. The only free vision model on OpenRouter that
    /// supports both `seed` and `structured_outputs`, which the scoring depends on.
    static let modelId = "nvidia/nemotron-3.5-super-vl:free"

    /// Pinned with fallbacks disabled so an outage fails the scan rather than rerouting it. This
    /// model has a single endpoint, so there is nothing to reroute to anyway (ADR 0001).
    static let provider = "Nvidia"

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
