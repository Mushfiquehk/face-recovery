import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @AppStorage(PinStore.enabledKey) private var lockEnabled = false
    @State private var pinFlow: PinFlowRequest?

    private struct PinFlowRequest: Identifiable {
        let mode: PinSetupFlow.Mode
        var id: Int { switch mode { case .create: 0; case .change: 1; case .disable: 2 } }
        static let create = PinFlowRequest(mode: .create)
        static let change = PinFlowRequest(mode: .change)
        static let disable = PinFlowRequest(mode: .disable)
    }

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-or-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, newValue in
                            KeychainStore.save(newValue)
                            testResult = nil
                        }

                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(apiKey.isEmpty || isTesting)

                    switch testResult {
                    case .success:
                        Label("Key accepted by OpenRouter.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                } header: {
                    Text("OpenRouter API key")
                } footer: {
                    Text("Stored in this device's Keychain. It is never written to the project or to a build setting.")
                }

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
                    // Shown so provenance is visible without reading the source. These are
                    // pinned in ScoringConfiguration and recorded on every Scoring Run.
                    ForEach(ScoringConfiguration.provenanceSummary, id: \.label) { item in
                        LabeledContent(item.label, value: item.value)
                            .monospaced()
                    }
                } header: {
                    Text("Scoring provenance")
                } footer: {
                    Text("Pinned in the build. Fallbacks are off: if \(ScoringConfiguration.provider) is down a scan fails rather than being scored by a different provider. Changing any of these makes new scans incomparable with old ones.")
                }

                Section {
                    Text("Photos are sent to OpenRouter for scoring. Review your OpenRouter account's prompt-logging and training settings before scanning a real face.")
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
        .onAppear {
            apiKey = KeychainStore.load() ?? ""
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            try await OpenRouterClient(apiKey: apiKey).testConnection()
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}
