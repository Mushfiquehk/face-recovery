import Foundation

/// Writes `export-<date>/` containing `scans.json` and the photo files. `scans.json` also
/// carries every Journal Entry, joined to scans by the local `day` both records share.
///
/// Derived values — Recovery Scores, Personal Baselines — are deliberately not exported. The
/// Python pipeline recomputes them from the same Absolute Signals, so the app and the analysis
/// cannot drift into disagreeing about how a score was produced.
enum ExportBuilder {
    struct Document: Encodable {
        let exportedAt: Date
        let schemaVersion: String
        let scans: [Record]
        let journalEntries: [JournalRecord]
    }

    struct Record: Encodable {
        struct Signals: Encodable {
            let underEyeDarkness: Int
            let underEyePuffiness: Int
            let facialPuffiness: Int
            let eyeRedness: Int
            let skinDullness: Int
            let holisticTiredness: Int
        }

        struct Quality: Encodable {
            let lighting: Int
            let sharpness: Int
            let faceFullyVisible: Bool
            let usable: Bool
        }

        struct Run: Encodable {
            let provider: String
            let modelId: String
            let seed: Int
            let promptVersion: String
            let schemaVersion: String
            let requestedAt: Date
            let rawResponseJson: String
        }

        let id: String
        /// Local calendar day, `yyyy-MM-dd`. `captured_at` is encoded in UTC, so without this
        /// the pipeline would have to guess the time zone to find the day a scan belongs to.
        let day: String
        let capturedAt: Date
        let isDateAdjusted: Bool
        let isBackfilled: Bool
        let isCanonical: Bool
        let canonicalDesignatedAt: Date?
        /// Filename of the photo in the same folder as `scans.json`.
        let photo: String
        let signals: Signals?
        let captureQuality: Quality?
        let scoringRun: Run?
    }

    /// A Journal Entry exactly as the user gave it. Ratings are the 1-5 raw values; skipped
    /// questions are omitted rather than written as null.
    struct JournalRecord: Encodable {
        let day: String
        let createdAt: Date
        let updatedAt: Date
        let isBlindToScore: Bool
        let perceivedRecovery: Int?
        let sleepQuality: Int?
        let hoursSlept: Int?
        let tookMedication: Bool?
        let medications: [String]
        let factors: [String]
        let notes: String
    }

    /// Builds the export folder and returns its URL, ready for the share sheet.
    static func build(scans: [FaceScan], journalEntries: [JournalEntry], now: Date = Date()) throws -> URL {
        let stamp = ISO8601DateFormatter.exportStamp.string(from: now)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(stamp)", isDirectory: true)

        // A stale folder from an earlier export today would otherwise mix two exports.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var records: [Record] = []
        for scan in scans.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            let source = PhotoStore.url(for: scan.photoFilename)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(
                at: source,
                to: folder.appendingPathComponent(scan.photoFilename)
            )
            records.append(record(for: scan))
        }

        let document = Document(
            exportedAt: now,
            schemaVersion: ScoringConfiguration.schemaVersion,
            scans: records,
            journalEntries: journalEntries
                .sorted { $0.dayStart < $1.dayStart }
                .map(journalRecord(for:))
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        try encoder.encode(document).write(
            to: folder.appendingPathComponent("scans.json"),
            options: .atomic
        )

        return folder
    }

    private static func record(for scan: FaceScan) -> Record {
        Record(
            id: scan.id.uuidString,
            day: DateFormatter.exportDay.string(from: scan.dayStart),
            capturedAt: scan.capturedAt,
            isDateAdjusted: scan.isDateAdjusted,
            isBackfilled: scan.isBackfilled,
            isCanonical: scan.isCanonical,
            canonicalDesignatedAt: scan.canonicalDesignatedAt,
            photo: scan.photoFilename,
            signals: scan.signals.map {
                Record.Signals(
                    underEyeDarkness: $0.underEyeDarkness,
                    underEyePuffiness: $0.underEyePuffiness,
                    facialPuffiness: $0.facialPuffiness,
                    eyeRedness: $0.eyeRedness,
                    skinDullness: $0.skinDullness,
                    holisticTiredness: $0.holisticTiredness
                )
            },
            captureQuality: scan.quality.map {
                Record.Quality(
                    lighting: $0.lighting,
                    sharpness: $0.sharpness,
                    faceFullyVisible: $0.faceFullyVisible,
                    usable: $0.isUsable
                )
            },
            scoringRun: scan.scoringRun.map {
                Record.Run(
                    provider: $0.provider,
                    modelId: $0.modelId,
                    seed: $0.seed,
                    promptVersion: $0.promptVersion,
                    schemaVersion: $0.schemaVersion,
                    requestedAt: $0.requestedAt,
                    rawResponseJson: $0.rawResponseJSON
                )
            }
        )
    }

    private static func journalRecord(for entry: JournalEntry) -> JournalRecord {
        JournalRecord(
            day: DateFormatter.exportDay.string(from: entry.dayStart),
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            isBlindToScore: entry.isBlindToScore,
            perceivedRecovery: entry.perceivedRecovery,
            sleepQuality: entry.sleepQuality,
            hoursSlept: entry.hoursSlept,
            tookMedication: entry.tookMedication,
            medications: entry.medications,
            factors: entry.factors,
            notes: entry.notes
        )
    }
}

private extension DateFormatter {
    /// In the device's time zone, unlike `ISO8601DateFormatter`, which defaults to UTC and would
    /// file a local-midnight `dayStart` east of Greenwich under the previous day.
    static let exportDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension ISO8601DateFormatter {
    static let exportStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
