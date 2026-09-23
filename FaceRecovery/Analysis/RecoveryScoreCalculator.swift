import Foundation

/// A Recovery Score together with the arithmetic that produced it, so the day detail screen
/// can show the user why the number is what it is.
struct RecoveryScore {
    let value: Int
    /// True when there was not yet enough history for a personalised number.
    let isBaselineForming: Bool
    /// Per-Signal deviation from the Personal Baseline. Positive = worse than normal.
    let deviations: [Signal: Double]
    let meanDeviation: Double
    /// Tracked and displayed separately; never folded into `value`.
    let holisticDeviation: Double
    let baseline: PersonalBaseline

    subscript(deviation signal: Signal) -> Double { deviations[signal] ?? 0 }
}

/// Converts stored Absolute Signals into a Recovery Score. Nothing here is persisted: the whole
/// point of ADR 0002 is that this is read-time arithmetic.
enum RecoveryScoreCalculator {
    /// Returns `nil` for a scan that has no Recovery Score: unscored, or an Unusable Scan.
    /// Unusable Scans are still stored and displayed, but scoring one would let lighting or
    /// framing be read as recovery.
    static func score(
        for scan: FaceScan,
        baseline: PersonalBaseline,
        tuning: ScoreTuning = .default
    ) -> RecoveryScore? {
        guard let signals = scan.signals, scan.isUsable else { return nil }

        var deviations: [Signal: Double] = [:]
        for signal in Signal.allCases {
            deviations[signal] = Double(signals[signal]) - baseline[signal]
        }

        let isBaselineForming = baseline.sampleCount < tuning.minimumScansForBaseline
        let meanDeviation = mean(Signal.allCases.map { deviations[$0] ?? 0 })

        let value: Double
        if isBaselineForming {
            // No meaningful baseline yet, so fall back to absolute appearance. Shown with a
            // "baseline forming" label so this is never mistaken for a personalised score.
            value = 100 - mean(signals.observed.map(Double.init))
        } else {
            value = tuning.atBaselineScore - tuning.deviationWeight * meanDeviation
        }

        return RecoveryScore(
            value: Int(min(100, max(0, value)).rounded()),
            isBaselineForming: isBaselineForming,
            deviations: deviations,
            meanDeviation: meanDeviation,
            holisticDeviation: Double(signals.holisticTiredness) - baseline.holisticTirednessMedian,
            baseline: baseline
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
