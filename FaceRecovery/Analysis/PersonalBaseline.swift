import Foundation

/// The trailing median of each Absolute Signal, representing what this user's face normally
/// looks like. Recomputable from stored measurements at any time.
struct PersonalBaseline {
    /// Median per Signal id.
    var medians: [String: Double]

    /// How many scans the medians were taken over. Below `minimumScansForBaseline` the user
    /// is Baseline Forming.
    var sampleCount: Int

    /// Only usable, non-Date-Adjusted Canonical Scans qualify: Unusable Scans would let
    /// lighting masquerade as a bad night, and Date-Adjusted scans have unreliable ordering.
    static func qualifies(_ scan: FaceScan) -> Bool {
        scan.isCanonical && scan.isUsable && !scan.isDateAdjusted
    }

    /// Builds the baseline for `scan` from the qualifying Canonical Scans of *earlier* days.
    ///
    /// Strictly earlier, deliberately: a baseline that included the day being predicted, or any
    /// day after it, would leak future information into a past prediction. The research strand
    /// compares these predictions with WHOOP day by day, and that comparison is only honest if
    /// each day's prediction could have been computed on that morning.
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
        let signalSets = scans.compactMap { $0.measurement?.measurement?.signals }

        var medians: [String: Double] = [:]
        for id in Set(signalSets.flatMap(\.keys)) {
            medians[id] = median(signalSets.compactMap { $0[id] })
        }
        return PersonalBaseline(medians: medians, sampleCount: signalSets.count)
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
