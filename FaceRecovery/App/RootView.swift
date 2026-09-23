import SwiftUI

struct RootView: View {
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
    }
}
