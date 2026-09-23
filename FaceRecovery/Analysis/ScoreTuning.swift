import Foundation

/// Every tunable constant in the Recovery Score, in one place. These are an out-of-the-box
/// starting point, not a calibrated finding. Because personalisation is arithmetic over stored
/// Absolute Signals (ADR 0002), changing them re-renders all history instantly and costs
/// nothing — no scan is ever re-scored.
struct ScoreTuning {
    /// How many qualifying Canonical Scans form the Personal Baseline.
    var baselineWindow: Int = 14

    /// Below this many qualifying scans the user is Baseline Forming and sees Absolute
    /// Signals directly rather than a personalised number.
    var minimumScansForBaseline: Int = 3

    /// A day exactly at baseline scores this.
    var atBaselineScore: Double = 70

    /// Points of Recovery Score lost per point of mean deviation above baseline.
    var deviationWeight: Double = 1.5

    static let `default` = ScoreTuning()
}
