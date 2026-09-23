import Foundation
import SwiftData

/// One invocation of the LLM against one Face Scan, recorded with everything needed to
/// reproduce or re-parse it. A scan's Absolute Signals are meaningless without it.
@Model
final class ScoringRun {
    var provider: String
    var modelId: String
    var seed: Int
    var promptVersion: String
    var schemaVersion: String
    var requestedAt: Date

    /// The response body exactly as returned, kept so a future schema change can re-parse
    /// old scans without re-scoring them.
    var rawResponseJSON: String

    var scan: FaceScan?

    init(
        provider: String,
        modelId: String,
        seed: Int,
        promptVersion: String,
        schemaVersion: String,
        requestedAt: Date,
        rawResponseJSON: String
    ) {
        self.provider = provider
        self.modelId = modelId
        self.seed = seed
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        self.rawResponseJSON = rawResponseJSON
    }
}
