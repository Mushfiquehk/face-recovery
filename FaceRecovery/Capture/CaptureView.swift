import SwiftUI
import SwiftData

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var camera = CameraController()
    @State private var phase: Phase = .framing

    private enum Phase {
        case framing
        case scoring(FaceScan)
        /// The scan is stored; only the Scoring Run failed, so a retry is always offered.
        case failed(FaceScan, String)
        case scored(FaceScan)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .framing:
                    framingView
                case .scoring:
                    ProgressView("Scoring…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let scan, let message):
                    failureView(scan: scan, message: message)
                case .scored(let scan):
                    ScanResultView(scan: scan, score: scoreForResult(scan)) { phase = .framing }
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
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

    private func failureView(scan: FaceScan, message: String) -> some View {
        VStack(spacing: 18) {
            if let image = PhotoStore.load(scan.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Label("Scoring failed", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("The photo is saved. Nothing is lost by retrying.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Retry scoring") {
                Task { await score(scan) }
            }
            .buttonStyle(.borderedProminent)

            Button("Back to camera") { phase = .framing }
        }
        .padding()
    }

    /// The result screen reads the new scan against the baseline of the days before it, the
    /// same arithmetic the history uses.
    private func scoreForResult(_ scan: FaceScan) -> RecoveryScore? {
        let all = (try? modelContext.fetch(FetchDescriptor<FaceScan>())) ?? []
        return RecoveryScoreCalculator.score(
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
            await score(scan)
        } catch {
            phase = .framing
        }
    }

    private func score(_ scan: FaceScan) async {
        phase = .scoring(scan)
        do {
            try await ScoringService(modelContext: modelContext).rescore(scan)
            phase = .scored(scan)
        } catch {
            phase = .failed(scan, error.localizedDescription)
        }
    }
}
