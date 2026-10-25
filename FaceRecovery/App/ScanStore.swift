import SwiftData

/// The one SwiftData store, shared by the app's window and its App Intents, so a Shortcuts
/// automation reads exactly the scans and Journal Entries the app shows.
enum ScanStore {
    /// Local store only. There is no iCloud on a Personal Team, so Export is the only backup.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: FaceScan.self, ScanMeasurement.self, SignalSet.self, CaptureQuality.self,
                ScoringRun.self, JournalEntry.self
            )
        } catch {
            fatalError("Could not open the scan store: \(error)")
        }
    }()
}
