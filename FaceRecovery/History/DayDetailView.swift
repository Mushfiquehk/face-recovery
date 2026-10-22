import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let day: DayEntry

    @State private var measuringID: UUID?
    @State private var errorMessage: String?
    @State private var selected: String?

    private var canonical: FaceScan { day.canonical }

    var body: some View {
        List {
            Section {
                RegionPhoto(scan: canonical, highlighted: selected)
                LabeledContent("Captured", value: canonical.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Daily Sleep Prediction") {
                if let prediction = day.dailyPrediction {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(prediction.value)")
                            .font(.system(size: 44, weight: .semibold).monospacedDigit())
                        VStack(alignment: .leading, spacing: 4) {
                            if prediction.isBaselineForming {
                                Text("Learning your usual face").font(.body.weight(.semibold))
                                Text("Fewer than \(ScoreTuning.default.minimumScansForBaseline) clear morning scans so far, so this is your average night rather than a reading of this photo.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(SleepBand(value: prediction.value).label)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SleepBand(value: prediction.value).color)
                                Text("Predicted WHOOP sleep performance. Your average night is \(Int(prediction.startingValue.rounded())).")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if canonical.isMeasured {
                    Text("No prediction: this photo did not count, so it is left out of the trend and of your usual face.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not read yet.").foregroundStyle(.secondary)
                }
            }

            Section {
                AudioReportButton(sentences: DailyReport.sentences(
                    dayStart: day.dayStart,
                    isMeasured: canonical.isMeasured,
                    prediction: day.dailyPrediction
                ))
            }

            if let prediction = day.dailyPrediction, !prediction.isBaselineForming {
                Section("Why this number") {
                    ContributionsView(prediction: prediction, selected: $selected)
                        .padding(.vertical, 4)
                }
            }

            Section("Journal") {
                JournalPanel(dayStart: day.dayStart)
            }

            if let measurement = canonical.measurement {
                Section("Photo check") {
                    PhotoCheckView(measurement: measurement)
                }

                Section {
                    LabeledContent("Measurement", value: measurement.version)
                    LabeledContent("Measured", value: measurement.measuredAt.formatted(date: .abbreviated, time: .shortened))
                    if let prediction = day.dailyPrediction {
                        LabeledContent("Sleep Model", value: prediction.modelVersion)
                    }
                } header: {
                    Text("How it was read")
                } footer: {
                    Text("Measured on this phone; the photo never left it.")
                }
                .font(.footnote)
            }

            Section {
                if !canonical.isMeasured {
                    Button("Read this scan") { measure(canonical) }
                        .disabled(measuringID != nil)
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
                    Text("The Canonical Scan is the one whose Sleep Prediction represents this day. It defaults to the earliest scan; re-designating another is recorded.")
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
                if !scan.isUsable && scan.isMeasured {
                    Text("Did not count").font(.caption2).foregroundStyle(.orange)
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

    private func measure(_ scan: FaceScan) {
        measuringID = scan.id
        errorMessage = nil
        Task {
            defer { measuringID = nil }
            do {
                try await ScoringService(modelContext: modelContext).measure(scan)
            } catch {
                errorMessage = "The photo could not be opened. Try again."
            }
        }
    }
}
