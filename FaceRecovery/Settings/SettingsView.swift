import SwiftUI

struct SettingsView: View {
    @AppStorage(PinStore.enabledKey) private var lockEnabled = false
    @AppStorage(FamilyUpdate.Setting.enabled.rawValue)
    private var familyUpdatesEnabled = FamilyUpdate.Setting.enabled.defaultValue
    @State private var pinFlow: PinFlowRequest?

    private struct PinFlowRequest: Identifiable {
        let mode: PinSetupFlow.Mode
        var id: Int { switch mode { case .create: 0; case .change: 1; case .disable: 2 } }
        static let create = PinFlowRequest(mode: .create)
        static let change = PinFlowRequest(mode: .change)
        static let disable = PinFlowRequest(mode: .disable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FamilyUpdateSettingsView()
                    } label: {
                        LabeledContent {
                            Text(familyUpdatesEnabled ? "On" : "Off")
                        } label: {
                            Label("Family updates", systemImage: "person.2.fill")
                        }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Send a short daily message to family or a friend. To share one day as a picture, open it and tap Share.")
                }

                Section {
                    if lockEnabled {
                        Button("Change PIN", systemImage: "lock.rotation") { pinFlow = .change }
                        Button("Turn off PIN lock", systemImage: "lock.open", role: .destructive) { pinFlow = .disable }
                    } else {
                        Button("Turn on PIN lock", systemImage: "lock") { pinFlow = .create }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(lockEnabled
                         ? "The app asks for your 4-digit PIN when it opens. A forgotten PIN cannot be recovered: deleting the app clears it, along with your scans."
                         : "Optional. Ask for a 4-digit PIN each time the app opens.")
                }

                Section {
                    NavigationLink {
                        SleepModelView()
                    } label: {
                        Label("How your sleep is read", systemImage: "face.dashed")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text(familyUpdatesEnabled
                         ? "Your photos are measured on this phone and never leave it. Nothing is sent to any server. Family updates go out as a text from your own Messages app, without photos or notes."
                         : "Your photos are measured on this phone and never leave it. Nothing is sent to any server.")
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $pinFlow) { request in
                PinSetupFlow(mode: request.mode)
            }
        }
    }
}

/// The Sleep Model and Measurement Version behind every reading, so provenance is visible
/// without reading the source. Every scan is re-measured when the Measurement Version changes,
/// so versions never mix.
private struct SleepModelView: View {
    private let model = SleepModel.bundled

    var body: some View {
        Form {
            Section {
                LabeledContent("Average night", value: "\(Int(model.startingValue.rounded()))")
                LabeledContent("WHOOP nights used", value: "\(model.nightsUsed)")
            } footer: {
                Text("Every reading starts from your average night and moves up or down with what your photo shows.")
            }

            Section {
                ForEach(model.signals) { signal in
                    LabeledContent(signal.name, value: String(format: "%+.1f", signal.weight))
                }
            } header: {
                Text("Points per part of your face")
            } footer: {
                Text(model.nightsUsed == 0
                     ? "Each number is how many points one typical change in that part of your face moves the reading. They come from research on how tired faces look and will be tuned to your own WHOOP nights once there are enough clear mornings."
                     : "Each number is how many points one typical change in that part of your face moves the reading, tuned to \(model.nightsUsed) of your WHOOP nights.")
            }

            Section("Versions") {
                LabeledContent("Measurement", value: FaceMeasurement.currentVersion)
                LabeledContent("Sleep Model", value: model.version)
            }
        }
        .navigationTitle("How your sleep is read")
        .navigationBarTitleDisplayMode(.inline)
    }
}
