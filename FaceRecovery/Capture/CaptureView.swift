import SwiftUI
import SwiftData

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var camera = CameraController()
    @State private var phase: Phase = .framing
    @State private var journalPrompt: JournalPrompt?
    /// The day the journal was last asked for, so a retake that day does not ask again, even
    /// if the user chose "Not now".
    @State private var journalAskedOn: Date?

    private struct JournalPrompt: Identifiable {
        let dayStart: Date
        var id: Date { dayStart }
    }

    private enum Phase {
        case framing
        case measuring(FaceScan)
        /// The scan is stored; only reading the photo failed, so a retry is always offered.
        case failed(FaceScan, friendly: String, detail: String)
        case measured(FaceScan)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .framing:
                    framingView
                case .measuring:
                    ProgressView("Reading your photo…")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let scan, let friendly, let detail):
                    failureView(scan: scan, friendly: friendly, detail: detail)
                case .measured(let scan):
                    ScanResultView(scan: scan, prediction: predictionForResult(scan)) { phase = .framing }
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $journalPrompt) { prompt in
            JournalFlowView(dayStart: prompt.dayStart, existing: nil, isBlindToScore: true)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var framingView: some View {
        switch camera.status {
        case .running:
            ZStack(alignment: .bottom) {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(edges: .top)
                FramingGuide()
                    .ignoresSafeArea(edges: .top)

                Button(action: { Task { await takeScan() } }) {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
                }
                .padding(.bottom, 28)
                .accessibilityLabel("Take face scan")
            }

        case .denied:
            ContentUnavailableView(
                "Camera access is off",
                systemImage: "camera.fill",
                description: Text("Allow camera access in Settings to take a Face Scan. You can still backfill from your photo library.")
            )

        case .failed(let message):
            ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text(message))

        case .idle:
            ProgressView()
        }
    }

    /// Written for older users: plain words, the reassurance first, two large buttons, and the
    /// technical detail kept out of the way. Scrolls so it still fits at accessibility sizes.
    private func failureView(scan: FaceScan, friendly: String, detail: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = PhotoStore.load(scan.photoFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }

                Label("Your photo could not be read", systemImage: "exclamationmark.triangle")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(friendly)
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text("Your photo is saved. Nothing is lost.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await measure(scan) }
                } label: {
                    Text("Try again")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    phase = .framing
                } label: {
                    Text("Back to camera")
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.bordered)

                DisclosureGroup("Technical details") {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(.body)
            }
            .padding()
        }
    }

    /// The result screen reads the new scan against the baseline of the days before it, the
    /// same arithmetic the history uses.
    private func predictionForResult(_ scan: FaceScan) -> SleepPrediction? {
        let all = (try? modelContext.fetch(FetchDescriptor<FaceScan>())) ?? []
        return SleepPredictor.predict(
            for: scan,
            baseline: PersonalBaseline.make(for: scan, from: all)
        )
    }

    private func takeScan() async {
        do {
            let image = try await camera.capture()
            let service = ScoringService(modelContext: modelContext)
            let scan = try service.store(
                image: image,
                capturedAt: Date(),
                isDateAdjusted: false,
                isBackfilled: false
            )
            askForJournal(on: scan.dayStart)
            await measure(scan)
        } catch {
            phase = .framing
        }
    }

    /// Opens the day's journal over the scan while it is read, so the user says how they feel
    /// before they see how they look (ADR 0004). Asked once a day, and only if not yet written.
    private func askForJournal(on dayStart: Date) {
        guard journalAskedOn != dayStart,
              JournalEntry.entry(on: dayStart, in: modelContext) == nil
        else { return }
        journalAskedOn = dayStart
        journalPrompt = JournalPrompt(dayStart: dayStart)
    }

    private func measure(_ scan: FaceScan) async {
        phase = .measuring(scan)
        do {
            try await ScoringService(modelContext: modelContext).measure(scan)
            phase = .measured(scan)
        } catch {
            phase = .failed(
                scan,
                friendly: "The photo could not be opened on this phone. Trying again usually fixes it.",
                detail: String(describing: error)
            )
        }
    }
}
