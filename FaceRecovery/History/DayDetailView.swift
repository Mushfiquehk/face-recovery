import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let day: DayEntry

    @State private var rescoringID: UUID?
    @State private var errorMessage: String?

    private var canonical: FaceScan { day.canonical }

    var body: some View {
        List {
            Section {
                if let image = PhotoStore.load(canonical.photoFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                LabeledContent("Captured", value: canonical.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Daily Recovery Score") {
                if let score = day.dailyRecoveryScore {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(score.value)")
                            .font(.system(size: 44, weight: .semibold).monospacedDigit())
                        VStack(alignment: .leading) {
                            if score.isBaselineForming {
                                Text("Baseline forming")
                                Text("Fewer than \(ScoreTuning.default.minimumScansForBaseline) qualifying scans, so this is read from Absolute Signals rather than from your Personal Baseline.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Personal Baseline over \(score.baseline.sampleCount) scan\(score.baseline.sampleCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("70 is exactly at baseline.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if canonical.isScored {
                    Text("No score: this is an Unusable Scan, so it is excluded from the trend and from your Personal Baseline.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not scored yet.").foregroundStyle(.secondary)
                }
            }

            if let signals = canonical.signals {
                Section("Absolute Signals") {
                    ScanReadingView(signals: signals, score: day.dailyRecoveryScore)
                        .padding(.vertical, 4)
                }
            }

            if let quality = canonical.quality {
                Section("Capture Quality") {
                    CaptureQualityView(quality: quality)
                }
            }

            if let run = canonical.scoringRun {
                Section {
                    LabeledContent("Provider", value: run.provider)
                    LabeledContent("Model", value: run.modelId)
                    LabeledContent("Seed", value: String(run.seed))
                    LabeledContent("Prompt", value: run.promptVersion)
                    LabeledContent("Schema", value: run.schemaVersion)
                    LabeledContent("Scored", value: run.requestedAt.formatted(date: .abbreviated, time: .shortened))
                } header: {
                    Text("Scoring Run")
                } footer: {
                    Text("Absolute Signals are meaningless without the Scoring Run that produced them, so both are exported together.")
                }
                .font(.footnote)
            }

            Section {
                if !canonical.isScored {
                    Button("Score this scan") { rescore(canonical) }
                        .disabled(rescoringID != nil)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            if day.hasMultipleScans {
                Section {
                    ForEach(day.allScans, id: \.id) { scan in
                        scanRow(scan)
                    }
                } header: {
                    Text("All scans this day")
                } footer: {
                    Text("The Canonical Scan is the one whose Recovery Score represents this day. It defaults to the earliest scan; re-designating another is recorded.")
                }
            }
        }
        .navigationTitle(day.dayStart.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scanRow(_ scan: FaceScan) -> some View {
        HStack(spacing: 12) {
            if let image = PhotoStore.load(scan.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.capturedAt.formatted(date: .omitted, time: .shortened))
                if scan.isCanonical {
                    Label(
                        scan.canonicalDesignatedAt == nil ? "Canonical (earliest)" : "Canonical (chosen)",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.tint)
                }
                if !scan.isUsable && scan.isScored {
                    Text("Unusable Scan").font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            if !scan.isCanonical {
                Button("Make canonical") { makeCanonical(scan) }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func makeCanonical(_ scan: FaceScan) {
        do {
            try ScoringService(modelContext: modelContext).makeCanonical(scan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rescore(_ scan: FaceScan) {
        rescoringID = scan.id
        errorMessage = nil
        Task {
            defer { rescoringID = nil }
            do {
                try await ScoringService(modelContext: modelContext).rescore(scan)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
