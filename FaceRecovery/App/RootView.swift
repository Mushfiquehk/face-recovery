import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PinStore.enabledKey) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    /// Starts locked when the lock is on, so a cold launch asks for the PIN.
    @State private var isLocked = UserDefaults.standard.bool(forKey: PinStore.enabledKey)

    var body: some View {
        TabView {
            Tab("History", systemImage: "list.bullet") {
                HistoryListView()
            }
            Tab("Scan", systemImage: "camera") {
                CaptureView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .overlay {
            if lockEnabled && isLocked {
                LockView { isLocked = false }
            } else if lockEnabled && scenePhase != .active {
                PrivacyCover()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && lockEnabled { isLocked = true }
        }
        // Scans from before on-device measurement, or from an older Measurement Version, are
        // re-measured from their stored photos so every Sleep Prediction uses one version.
        .task { await ScoringService(modelContext: modelContext).measureStaleScans() }
    }
}
