import Foundation

/// Maintains the invariant that exactly one Face Scan per day is the Canonical Scan.
enum CanonicalScan {
    /// Earliest scan of the day by default; a user re-designation wins and is kept even when a
    /// scan with an earlier timestamp is backfilled afterwards.
    static func reconcile(_ dayScans: [FaceScan]) {
        guard !dayScans.isEmpty else { return }

        let designated = dayScans
            .filter { $0.canonicalDesignatedAt != nil }
            .max { ($0.canonicalDesignatedAt ?? .distantPast) < ($1.canonicalDesignatedAt ?? .distantPast) }

        let chosen = designated ?? dayScans.min { $0.capturedAt < $1.capturedAt }

        for scan in dayScans {
            scan.isCanonical = scan.id == chosen?.id
        }
    }

    /// Records a deliberate choice of Canonical Scan for a day.
    static func designate(_ scan: FaceScan, among dayScans: [FaceScan]) {
        for other in dayScans where other.id != scan.id {
            other.canonicalDesignatedAt = nil
        }
        scan.canonicalDesignatedAt = .now
        reconcile(dayScans)
    }
}
