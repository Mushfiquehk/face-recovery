import Foundation

/// How much one Signal moved a Sleep Prediction, given how far it was from the user's usual.
struct Contribution: Identifiable {
    let signal: SleepModel.SignalWeight
    /// Today's value minus the Personal Baseline, in typical day-to-day differences.
    let deviation: Double
    /// Points added to (positive) or taken from (negative) the Sleep Prediction.
    let points: Double

    var id: String { signal.id }
    var words: String { deviation >= 0 ? signal.higherMeans : signal.lowerMeans }
    /// Too small a change to mention.
    var isSteady: Bool { abs(deviation) < 0.5 }
}

/// A Sleep Prediction with the arithmetic that produced it, so every point can be shown.
struct SleepPrediction {
    let value: Int
    /// Too little history for a Personal Baseline: the value is the model's starting value and
    /// there are no Contributions yet.
    let isBaselineForming: Bool
    let startingValue: Double
    /// Largest effect first.
    let contributions: [Contribution]
    let baseline: PersonalBaseline
    let modelVersion: String

    /// The starting value plus every Contribution, before the 0-100 cap.
    var uncappedValue: Double { startingValue + contributions.reduce(0) { $0 + $1.points } }
    var isCapped: Bool { uncappedValue < 0 || uncappedValue > 100 }
}

/// Read-time arithmetic, like the Personal Baseline it depends on: nothing here is stored, so a
/// new Sleep Model re-renders the whole history instantly.
enum SleepPredictor {
    /// Nil for a scan with no Sleep Prediction: not yet measured, or an Unusable Scan, whose
    /// lighting or framing would otherwise be read as a bad night.
    static func predict(
        for scan: FaceScan,
        baseline: PersonalBaseline,
        model: SleepModel = .bundled,
        tuning: ScoreTuning = .default
    ) -> SleepPrediction? {
        guard scan.isUsable, let signals = scan.measurement?.measurement?.signals else { return nil }

        let isBaselineForming = baseline.sampleCount < tuning.minimumScansForBaseline
        var contributions: [Contribution] = []
        if !isBaselineForming {
            for weight in model.signals where weight.typicalDeviation > 0 {
                guard let value = signals[weight.id], let usual = baseline.medians[weight.id] else { continue }
                let deviation = (value - usual) / weight.typicalDeviation
                let clamped = min(max(deviation, -model.contributionClamp), model.contributionClamp)
                contributions.append(Contribution(signal: weight, deviation: deviation, points: weight.weight * clamped))
            }
        }

        let total = model.startingValue + contributions.reduce(0) { $0 + $1.points }
        return SleepPrediction(
            value: Int(min(100, max(0, total)).rounded()),
            isBaselineForming: isBaselineForming,
            startingValue: model.startingValue,
            contributions: contributions.sorted { abs($0.points) > abs($1.points) },
            baseline: baseline,
            modelVersion: model.version
        )
    }
}
