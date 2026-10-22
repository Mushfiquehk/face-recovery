import Foundation

/// The starting value and per-Signal weights that turn a scan's Signals into a Sleep Prediction.
/// Fitted on the Mac by `face-pipeline autoresearch` and shipped as `SleepModel.json`; the app
/// never fits anything itself (ADR 0005).
struct SleepModel: Codable {
    struct SignalWeight: Codable, Identifiable {
        /// A key of `FaceMeasurement.signals`.
        let id: String
        /// What the user sees, e.g. "Darkness under the eyes".
        let name: String
        /// Plain words for a value above / below the user's usual, e.g. "darker under the eyes".
        let higherMeans: String
        let lowerMeans: String
        /// A typical day-to-day difference in this Signal; deviations are counted in these.
        let typicalDeviation: Double
        /// Points of Sleep Prediction per typical difference above the usual.
        let weight: Double
    }

    let version: String
    let measurementVersion: String
    /// How the weights were set, in words: from the prior only, or fitted to WHOOP nights.
    let method: String
    let nightsUsed: Int
    /// The prediction for a face exactly like its Personal Baseline: the user's average night.
    let startingValue: Double
    /// No single Signal may move the prediction by more than this many typical differences.
    let contributionClamp: Double
    let signals: [SignalWeight]

    static let bundled: SleepModel = {
        guard let url = Bundle.main.url(forResource: "SleepModel", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(SleepModel.self, from: data)
        else { fatalError("SleepModel.json is missing from the app bundle or unreadable.") }
        return model
    }()
}
