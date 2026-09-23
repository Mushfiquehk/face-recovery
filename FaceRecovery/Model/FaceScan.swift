import Foundation
import SwiftData

/// A single photo of the user's face submitted for scoring, with the date and time it was
/// captured. Scans are never overwritten or deleted.
@Model
final class FaceScan {
    /// Stable identity, also used to name the photo file on disk.
    @Attribute(.unique) var id: UUID

    /// From EXIF when the photo carries it, otherwise set by the user.
    var capturedAt: Date

    /// True when `capturedAt` did not come from EXIF. Permanent; excludes the scan from
    /// research exports by default.
    var isDateAdjusted: Bool

    /// True when the scan came from the photo library rather than a live capture.
    var isBackfilled: Bool

    /// Filename relative to `PhotoStore`'s scans directory.
    var photoFilename: String

    /// Local start-of-day for `capturedAt`, stored so days can be grouped and queried
    /// without recomputing calendar arithmetic across the whole history.
    var dayStart: Date

    /// Whether this scan represents its day. Exactly one scan per day is canonical.
    var isCanonical: Bool

    /// Set when the user re-designated the Canonical Scan for this day, so that the
    /// default (earliest of the day) can be told apart from a deliberate choice.
    var canonicalDesignatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SignalSet.scan)
    var signals: SignalSet?

    @Relationship(deleteRule: .cascade, inverse: \CaptureQuality.scan)
    var quality: CaptureQuality?

    @Relationship(deleteRule: .cascade, inverse: \ScoringRun.scan)
    var scoringRun: ScoringRun?

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        isDateAdjusted: Bool,
        isBackfilled: Bool,
        photoFilename: String,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.isDateAdjusted = isDateAdjusted
        self.isBackfilled = isBackfilled
        self.photoFilename = photoFilename
        self.dayStart = calendar.startOfDay(for: capturedAt)
        self.isCanonical = false
        self.canonicalDesignatedAt = nil
    }

    /// A scan has been scored when it has both Absolute Signals and the Scoring Run that
    /// produced them. Signals without their provenance are meaningless (CONTEXT.md).
    var isScored: Bool { signals != nil && scoringRun != nil }

    /// Usable scans are the only ones that feed the Personal Baseline and trends.
    /// An unscored scan is not usable because nothing has judged its Capture Quality yet.
    var isUsable: Bool { isScored && (quality?.isUsable ?? false) }

    /// Research exports default to EXIF-dated scans only.
    var isResearchGrade: Bool { isUsable && !isDateAdjusted }

    /// Keeps `dayStart` consistent when the user edits a Backfill date.
    func updateCapturedAt(_ date: Date, isDateAdjusted: Bool, calendar: Calendar = .current) {
        capturedAt = date
        dayStart = calendar.startOfDay(for: date)
        if isDateAdjusted { self.isDateAdjusted = true }
    }
}
