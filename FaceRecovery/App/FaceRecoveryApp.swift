import SwiftUI
import SwiftData

@main
struct FaceRecoveryApp: App {
    /// Local store only. There is no iCloud on a Personal Team, so Export is the only backup.
    let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: FaceScan.self, SignalSet.self, CaptureQuality.self, ScoringRun.self
            )
        } catch {
            fatalError("Could not open the scan store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
