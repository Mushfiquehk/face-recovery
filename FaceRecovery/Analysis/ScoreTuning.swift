import Foundation

/// The tunable constants of the Personal Baseline. The Sleep Prediction's own numbers (starting
/// value, weights) live in `SleepModel.json`. Because personalisation is arithmetic over stored
/// measurements, changing these re-renders all history instantly and nothing is re-measured.
struct ScoreTuning {
    /// How many qualifying Canonical Scans form the Personal Baseline.
    var baselineWindow: Int = 14

    /// Below this many qualifying scans the user is Baseline Forming and every Sleep
    /// Prediction is provisional.
    var minimumScansForBaseline: Int = 3

    static let `default` = ScoreTuning()
}
