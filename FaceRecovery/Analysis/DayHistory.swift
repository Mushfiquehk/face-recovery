import Foundation

/// One day of history: its Canonical Scan, that scan's Daily Recovery Score, and any other
/// scans taken the same day.
struct DayEntry: Identifiable {
    let dayStart: Date
    let canonical: FaceScan
    let otherScans: [FaceScan]
    /// Nil when the Canonical Scan is unscored or an Unusable Scan.
    let dailyRecoveryScore: RecoveryScore?

    var id: Date { dayStart }
    var allScans: [FaceScan] { [canonical] + otherScans }
    var hasMultipleScans: Bool { !otherScans.isEmpty }
}

/// Assembles the history list. Days with no Face Scan simply do not appear — they are gaps,
/// never interpolated, because an interpolated recovery day is a fabricated observation.
enum DayHistory {
    static func build(from scans: [FaceScan], tuning: ScoreTuning = .default) -> [DayEntry] {
        let byDay = Dictionary(grouping: scans, by: \.dayStart)

        return byDay.keys.sorted(by: >).compactMap { dayStart -> DayEntry? in
            guard let dayScans = byDay[dayStart], !dayScans.isEmpty else { return nil }

            let ordered = dayScans.sorted { $0.capturedAt < $1.capturedAt }
            guard let canonical = ordered.first(where: \.isCanonical) ?? ordered.first else {
                return nil
            }

            let baseline = PersonalBaseline.make(for: canonical, from: scans, tuning: tuning)
            return DayEntry(
                dayStart: dayStart,
                canonical: canonical,
                otherScans: ordered.filter { $0.id != canonical.id },
                dailyRecoveryScore: RecoveryScoreCalculator.score(
                    for: canonical, baseline: baseline, tuning: tuning
                )
            )
        }
    }
}
