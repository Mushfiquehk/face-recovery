import Foundation

/// One day of history: its Canonical Scan, that scan's Daily Sleep Prediction, and any other
/// scans taken the same day.
struct DayEntry: Identifiable {
    let dayStart: Date
    let canonical: FaceScan
    let otherScans: [FaceScan]
    /// Nil when the Canonical Scan is unmeasured or an Unusable Scan.
    let dailyPrediction: SleepPrediction?

    var id: Date { dayStart }
    var allScans: [FaceScan] { [canonical] + otherScans }
    var hasMultipleScans: Bool { !otherScans.isEmpty }
}

/// Assembles the history list. Days with no Face Scan simply do not appear — they are gaps,
/// never interpolated, because an interpolated day is a fabricated observation.
enum DayHistory {
    static func build(from scans: [FaceScan], tuning: ScoreTuning = .default) -> [DayEntry] {
        let byDay = Dictionary(grouping: scans, by: \.dayStart)

        return byDay.keys.sorted(by: >).compactMap { dayStart -> DayEntry? in
            entry(for: dayStart, dayScans: byDay[dayStart] ?? [], allScans: scans, tuning: tuning)
        }
    }

    /// One day on its own, for callers that need a single day without building the whole
    /// history. Nil when the day has no Face Scan.
    static func day(_ dayStart: Date, from scans: [FaceScan], tuning: ScoreTuning = .default) -> DayEntry? {
        entry(for: dayStart, dayScans: scans.filter { $0.dayStart == dayStart }, allScans: scans, tuning: tuning)
    }

    private static func entry(
        for dayStart: Date,
        dayScans: [FaceScan],
        allScans: [FaceScan],
        tuning: ScoreTuning
    ) -> DayEntry? {
        let ordered = dayScans.sorted { $0.capturedAt < $1.capturedAt }
        guard let canonical = ordered.first(where: \.isCanonical) ?? ordered.first else {
            return nil
        }

        let baseline = PersonalBaseline.make(for: canonical, from: allScans, tuning: tuning)
        return DayEntry(
            dayStart: dayStart,
            canonical: canonical,
            otherScans: ordered.filter { $0.id != canonical.id },
            dailyPrediction: SleepPredictor.predict(for: canonical, baseline: baseline, tuning: tuning)
        )
    }
}
