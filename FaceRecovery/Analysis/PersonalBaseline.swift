import Foundation

/// The trailing median of each Absolute Signal, representing what this user's face normally
/// looks like. Recomputable from stored Absolute Signals at any time.
struct PersonalBaseline {
    /// Median per Signal. Holistic Tiredness is baselined too, so it can be compared against
    /// WHOOP Recovery independently, but it never enters the Recovery Score.
    var medians: [Signal: Double]
    var holisticTirednessMedian: Double

    /// How many scans the medians were taken over. Below `minimumScansForBaseline` the user
    /// is Baseline Forming.
    var sampleCount: Int

    subscript(signal: Signal) -> Double { medians[signal] ?? 0 }

    /// Only usable, non-Date-Adjusted Canonical Scans qualify: Unusable Scans would let
    /// lighting masquerade as recovery, and Date-Adjusted scans have unreliable ordering.
    static func qualifies(_ scan: FaceScan) -> Bool {
        scan.isCanonical && scan.isUsable && !scan.isDateAdjusted
    }

    /// Builds the baseline for `scan` from the qualifying Canonical Scans of *earlier* days.
    ///
    /// Strictly earlier, deliberately: a baseline that included the day being scored, or any
    /// day after it, would leak future information into a past score. The research strand
    /// compares these scores against WHOOP Recovery day by day, and that comparison is only
    /// honest if each day's score could have been computed on that morning.
    static func make(
        for scan: FaceScan,
        from history: [FaceScan],
        tuning: ScoreTuning = .default
    ) -> PersonalBaseline {
        let priorScans = history
            .filter { qualifies($0) && $0.dayStart < scan.dayStart }
            .sorted { $0.dayStart > $1.dayStart }
            .prefix(tuning.baselineWindow)

        return make(from: Array(priorScans))
    }

    /// Builds a baseline from an explicit set of scans, which are assumed to qualify already.
    static func make(from scans: [FaceScan]) -> PersonalBaseline {
        let signalSets = scans.compactMap(\.signals)

        var medians: [Signal: Double] = [:]
        for signal in Signal.allCases {
            medians[signal] = median(signalSets.map { Double($0[signal]) })
        }

        return PersonalBaseline(
            medians: medians,
            holisticTirednessMedian: median(signalSets.map { Double($0.holisticTiredness) }),
            sampleCount: signalSets.count
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
