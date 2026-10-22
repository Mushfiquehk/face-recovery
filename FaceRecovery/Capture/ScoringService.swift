import Foundation
import OSLog
import SwiftData
import UIKit

/// Turns a photograph into a stored, measured Face Scan.
///
/// The photo is persisted before it is measured, so a failure never loses a capture: the scan is
/// stored unmeasured and the UI offers a retry. Scans are never deleted. Measuring happens on the
/// device; no photo leaves the phone (ADR 0005).
@MainActor
final class ScoringService {
    private static let log = Logger(subsystem: "com.mushfique.facerecovery", category: "measurement")

    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Persists the photo as a Face Scan without measuring it.
    ///
    /// Callers that want to offer a retry should use this and then `measure`, so that a
    /// failure still leaves them holding the stored scan.
    @discardableResult
    func store(
        image: UIImage,
        capturedAt: Date,
        isDateAdjusted: Bool,
        isBackfilled: Bool
    ) throws -> FaceScan {
        let id = UUID()
        let filename = try PhotoStore.save(image, id: id)

        let scan = FaceScan(
            id: id,
            capturedAt: capturedAt,
            isDateAdjusted: isDateAdjusted,
            isBackfilled: isBackfilled,
            photoFilename: filename,
            calendar: calendar
        )
        modelContext.insert(scan)
        reconcileDay(of: scan)
        try modelContext.save()
        return scan
    }

    /// Stores the photo and measures it. Throws if measuring fails — the scan is still saved.
    @discardableResult
    func ingest(
        image: UIImage,
        capturedAt: Date,
        isDateAdjusted: Bool,
        isBackfilled: Bool
    ) async throws -> FaceScan {
        let scan = try store(
            image: image,
            capturedAt: capturedAt,
            isDateAdjusted: isDateAdjusted,
            isBackfilled: isBackfilled
        )
        try await measure(scan)
        return scan
    }

    /// Measures an already-stored scan on the device and attaches the result.
    ///
    /// A re-measure replaces the scan's measurement rather than adding a second one: a scan has
    /// exactly one set of Absolute Signals (CONTEXT.md). Measuring is deterministic, so the same
    /// photo always gives the same Signals. A photo with no face is stored as an Unusable Scan;
    /// only a photo that cannot be read at all throws.
    func measure(_ scan: FaceScan) async throws {
        let url = PhotoStore.url(for: scan.photoFilename)
        let measured: FaceMeasurement? = try await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { throw FaceMeasurementError.unreadableImage }
            do {
                return try FaceMeasurer.measure(imageData: data)
            } catch FaceMeasurementError.noFace {
                return nil
            }
        }.value

        if let old = scan.measurement { modelContext.delete(old) }
        scan.measurement = measured.map { ScanMeasurement($0) } ?? ScanMeasurement(noFaceAt: .now)
        try modelContext.save()
    }

    /// Measures every scan that has no measurement from the current Measurement Version: scans
    /// from before on-device measurement, or from an older version. Run at launch; quietly skips
    /// any photo that cannot be read, which the day screen then offers to retry.
    func measureStaleScans() async {
        let scans = (try? modelContext.fetch(FetchDescriptor<FaceScan>(sortBy: [SortDescriptor(\.capturedAt)]))) ?? []
        for scan in scans where !scan.isMeasured {
            do {
                try await measure(scan)
            } catch {
                Self.log.error("Could not measure \(scan.photoFilename, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Applies a corrected Backfill date and moves the scan to its new day, reconciling the
    /// Canonical Scan of both the day it left and the day it joined.
    func adjustDate(of scan: FaceScan, to newDate: Date) throws {
        let previousDay = scan.dayStart
        scan.updateCapturedAt(newDate, isDateAdjusted: true, calendar: calendar)
        reconcileDay(startingAt: previousDay)
        reconcileDay(of: scan)
        try modelContext.save()
    }

    func makeCanonical(_ scan: FaceScan) throws {
        CanonicalScan.designate(scan, among: scans(on: scan.dayStart))
        try modelContext.save()
    }

    private func reconcileDay(of scan: FaceScan) {
        reconcileDay(startingAt: scan.dayStart)
    }

    private func reconcileDay(startingAt dayStart: Date) {
        CanonicalScan.reconcile(scans(on: dayStart))
    }

    private func scans(on dayStart: Date) -> [FaceScan] {
        let descriptor = FetchDescriptor<FaceScan>(
            predicate: #Predicate { $0.dayStart == dayStart },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
