import Foundation
import SwiftData

/// A Face Scan's Absolute Signals and Capture Quality as measured on the device, with the
/// Measurement Version that produced them (ADR 0005). Photos are kept, so a new Measurement
/// Version replaces this record rather than sitting beside it: versions are never mixed.
@Model
final class ScanMeasurement {
    var version: String
    var measuredAt: Date

    /// False when no face was found or Capture Quality fell short; `problems` says why.
    var isUsable: Bool

    /// Plain-language reasons the scan is unusable, written for the user to act on.
    var problems: [String]

    /// The encoded `FaceMeasurement`. Nil when no face was found, so there was nothing to measure.
    var payload: Data?

    var scan: FaceScan?

    init(_ measurement: FaceMeasurement, at date: Date = .now) {
        version = measurement.version
        measuredAt = date
        isUsable = measurement.quality.usable
        problems = measurement.quality.problems
        payload = try? JSONEncoder().encode(measurement)
    }

    /// A photo in which Apple Vision found no face. Stored so it is not re-measured every launch.
    init(noFaceAt date: Date = .now) {
        version = FaceMeasurement.currentVersion
        measuredAt = date
        isUsable = false
        problems = ["No face was found. Hold the phone in front of your face."]
        payload = nil
    }

    var measurement: FaceMeasurement? {
        payload.flatMap { try? JSONDecoder().decode(FaceMeasurement.self, from: $0) }
    }
}
