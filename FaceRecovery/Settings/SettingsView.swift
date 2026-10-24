import SwiftUI

struct SettingsView: View {
    @AppStorage(PinStore.enabledKey) private var lockEnabled = false
    @AppStorage(FamilyUpdate.Setting.enabled.rawValue)
    private var familyUpdatesEnabled = FamilyUpdate.Setting.enabled.defaultValue
    @State private var pinFlow: PinFlowRequest?

    private let model = SleepModel.bundled

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
                    if lockEnabled {
                        Button("Change PIN") { pinFlow = .change }
                        Button("Turn off PIN lock", role: .destructive) { pinFlow = .disable }
                    } else {
                        Button("Turn on PIN lock") { pinFlow = .create }
                    }
                } header: {
                    Text("PIN lock")
                } footer: {
                    Text(lockEnabled
                         ? "The app asks for your 4-digit PIN when it opens. A forgotten PIN cannot be recovered: deleting the app clears it, along with your scans."
                         : "Optional. Ask for a 4-digit PIN each time the app opens.")
                }

                Section {
                    NavigationLink {
                        FamilyUpdateSettingsView()
                    } label: {
                        LabeledContent("Family updates", value: familyUpdatesEnabled ? "On" : "Off")
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Send a short daily message to family or a friend.")
                }

                Section {
                    // Shown so provenance is visible without reading the source. Every scan is
                    // re-measured when the Measurement Version changes, so versions never mix.
                    LabeledContent("Measurement", value: FaceMeasurement.currentVersion)
                    LabeledContent("Sleep Model", value: model.version)
                    LabeledContent("Average night", value: "\(Int(model.startingValue.rounded()))")
                    LabeledContent("WHOOP nights used", value: "\(model.nightsUsed)")
                    ForEach(model.signals) { signal in
                        LabeledContent(signal.name, value: String(format: "%+.1f", signal.weight))
                    }
                } header: {
                    Text("How your sleep is read")
                } footer: {
                    Text(model.nightsUsed == 0
                         ? "Each number is how many points one typical change in that part of your face moves the reading. They come from research on how tired faces look and will be tuned to your own WHOOP nights once there are enough clear mornings."
                         : "Each number is how many points one typical change in that part of your face moves the reading, tuned to \(model.nightsUsed) of your WHOOP nights.")
                }

                Section {
                    Text(familyUpdatesEnabled
                         ? "Your photos are measured on this phone and never leave it. Nothing is sent to any server. Family updates go out as a text from your own Messages app, without photos or notes."
                         : "Your photos are measured on this phone and never leave it. Nothing is sent to any server.")
                        .font(.footnote)
                } header: {
                    Text("Data handling")
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $pinFlow) { request in
                PinSetupFlow(mode: request.mode)
            }
        }
    }
}
