import SwiftUI
import SwiftData

@main
struct FaceRecoveryApp: App {
    init() {
        PinStore.reconcile()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(ScanStore.container)
    }
}
