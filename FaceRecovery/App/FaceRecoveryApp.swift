import SwiftUI
import SwiftData

@main
struct FaceRecoveryApp: App {
    init() {
        PinStore.reconcile()
        PhotoStore.protectExistingPhotos()
        ExportBuilder.removeLeftoverExports()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(ScanStore.container)
    }
}
