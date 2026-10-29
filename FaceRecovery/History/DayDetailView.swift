import SwiftUI
import SwiftData

/// One day from History, laid out like the scan result so a day reads the same way however it
/// was opened: the header, Listen and Share, why the number is what it is, the journal, then the
/// photo check and the other scans of the day.
struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let day: DayEntry

    @State private var measuringID: UUID?
    @State private var errorMessage: String?
    @State private var selected: String?

    private var canonical: FaceScan { day.canonical }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PredictionHeader(scan: canonical, prediction: day.dailyPrediction)

                if canonical.isMeasured {
                    DayActions(dayStart: day.dayStart, scan: canonical, prediction: day.dailyPrediction)
                } else {
                    readButton
                }

                if let measurement = canonical.measurement, !measurement.isUsable {
                    TitledCard(title: "Photo check") {
                        PhotoCheckView(measurement: measurement)
                    }
                }

                if let prediction = day.dailyPrediction, !prediction.isBaselineForming {
                    TitledCard(title: "Why this number") {
                        RegionPhoto(scan: canonical, highlighted: selected)
                            .frame(maxHeight: 320)
                        ContributionsView(prediction: prediction, selected: $selected)
                        SignalBreakdownLink(scan: canonical, prediction: prediction)
                            .buttonStyle(.bordered)
                    }
                } else {
                    RegionPhoto(scan: canonical, highlighted: nil)
                        .frame(maxHeight: 320)
                }

                TitledCard(title: "Journal") {
                    JournalPanel(dayStart: day.dayStart)
                }

                if let measurement = canonical.measurement, measurement.isUsable {
                    TitledCard(title: "Photo check") {
                        PhotoCheckView(measurement: measurement)
                    }
                }

                if day.hasMultipleScans {
                    TitledCard(title: "All scans this day") {
                        ForEach(day.allScans, id: \.id) { scan in
                            if scan.id != day.allScans.first?.id { Divider() }
                            scanRow(scan)
                        }
                        if canonical.isMeasured, let errorMessage {
                            Text(errorMessage).font(.callout).foregroundStyle(Palette.low)
                        }
                        Text("One scan counts for each day. It starts as the earliest; switching to another is recorded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let measurement = canonical.measurement {
                    provenance(measurement)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(day.dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readButton: some View {
        VStack(spacing: 8) {
            Button {
                measure(canonical)
            } label: {
                Group {
                    if measuringID != nil {
                        ProgressView()
                    } else {
                        Label("Read this scan", systemImage: "wand.and.stars")
                    }
                }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(measuringID != nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Palette.low)
            }
        }
    }

    /// Versions, small and last: there to be checked, not read every day.
    private func provenance(_ measurement: ScanMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Measured on this phone; the photo never left it.")
            Text("Measurement \(measurement.version), \(measurement.measuredAt.formatted(date: .abbreviated, time: .shortened))")
            if let prediction = day.dailyPrediction {
                Text("Sleep Model \(prediction.modelVersion)")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func scanRow(_ scan: FaceScan) -> some View {
        HStack(spacing: 12) {
            if let image = PhotoStore.thumbnail(scan.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.capturedAt.formatted(date: .omitted, time: .shortened))
                    .font(.body.weight(.semibold))
                if scan.isCanonical {
                    Label(
                        scan.canonicalDesignatedAt == nil ? "Counts for this day (earliest)" : "Counts for this day",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.tint)
                }
                if !scan.isUsable && scan.isMeasured {
                    Text("Did not count").font(.callout).foregroundStyle(Palette.caution)
                }
            }

            Spacer(minLength: 8)

            if !scan.isCanonical {
                Button("Count this one") { makeCanonical(scan) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(minHeight: 56)
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
