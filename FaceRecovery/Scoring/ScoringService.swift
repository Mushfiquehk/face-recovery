import Foundation
import SwiftData
import UIKit

/// Turns a photograph into a stored, scored Face Scan.
///
/// The photo is persisted before the network call, so a scoring failure never loses a capture:
/// the scan is stored unscored and the UI offers a retry (ADR 0001). Scans are never deleted.
@MainActor
final class ScoringService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Persists the photo as a Face Scan without scoring it.
    ///
    /// Callers that want to offer a retry should use this and then `rescore`, so that a
    /// scoring failure still leaves them holding the stored scan.
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

    /// Stores the photo and scores it. Throws if scoring fails — the scan is still saved.
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
        try await rescore(scan)
        return scan
    }

    /// Runs a Scoring Run against an already-stored scan and attaches the result.
    ///
    /// A re-score replaces the scan's Absolute Signals rather than adding a second set: a scan
    /// has exactly one set of Absolute Signals (CONTEXT.md). Re-scoring an unchanged photo with
    /// the pinned provider and fixed seed should return identical Signals; that is the
    /// determinism check in the validation plan.
    func rescore(_ scan: FaceScan) async throws {
        guard let apiKey = KeychainStore.load() else { throw ScoringError.missingAPIKey }
        guard let image = PhotoStore.load(scan.photoFilename) else {
            throw ScoringError.imageEncodingFailed
        }

        let payload = try PhotoStore.scoringPayload(for: image)
        let client = OpenRouterClient(apiKey: apiKey)
        let requestedAt = Date()
        let completion = try await client.score(imageData: payload)

        scan.signals = completion.response.makeSignalSet()
        scan.quality = completion.response.makeCaptureQuality()
        scan.scoringRun = ScoringRun(
            provider: completion.servedBy,
            modelId: ScoringConfiguration.modelId,
            seed: ScoringConfiguration.seed,
            promptVersion: ScoringConfiguration.promptVersion,
            schemaVersion: ScoringConfiguration.schemaVersion,
            requestedAt: requestedAt,
            rawResponseJSON: completion.rawJSON
        )
        try modelContext.save()
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
