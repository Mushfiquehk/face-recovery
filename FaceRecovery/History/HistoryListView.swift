import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \FaceScan.capturedAt, order: .reverse) private var scans: [FaceScan]
    @State private var isBackfilling = false
    @State private var isExporting = false

    private var days: [DayEntry] { DayHistory.build(from: scans) }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No scans yet",
                        systemImage: "face.smiling",
                        description: Text("Take a scan, or backfill from your photo library to build a baseline straight away.")
                    )
                } else {
                    List {
                        // Days with no Face Scan are absent rather than interpolated: a day
                        // with no observation has no Daily Recovery Score.
                        ForEach(days) { day in
                            NavigationLink(value: day.dayStart) {
                                DayRow(day: day)
                            }
                        }
                    }
                    .navigationDestination(for: Date.self) { dayStart in
                        if let day = days.first(where: { $0.dayStart == dayStart }) {
                            DayDetailView(day: day)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Backfill", systemImage: "photo.on.rectangle") {
                        isBackfilling = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        isExporting = true
                    }
                    .disabled(scans.isEmpty)
                }
            }
            .sheet(isPresented: $isBackfilling) { BackfillView() }
            .sheet(isPresented: $isExporting) { ExportView(scans: scans) }
        }
    }
}

private struct DayRow: View {
    let day: DayEntry

    var body: some View {
        HStack(spacing: 14) {
            if let image = PhotoStore.load(day.canonical.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(day.dayStart.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)

                if let score = day.dailyRecoveryScore, score.isBaselineForming {
                    Text("Baseline forming")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if day.dailyRecoveryScore == nil {
                    Text(day.canonical.isScored ? "Unusable Scan" : "Not scored")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 6) {
                    if day.hasMultipleScans {
                        Label("\(day.allScans.count)", systemImage: "square.stack")
                    }
                    if day.canonical.isDateAdjusted {
                        Label("Date-Adjusted", systemImage: "calendar.badge.exclamationmark")
                    }
                    if day.canonical.isBackfilled {
                        Label("Backfilled", systemImage: "clock.arrow.circlepath")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let score = day.dailyRecoveryScore {
                Text("\(score.value)")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(score.isBaselineForming ? .secondary : .primary)
            } else {
                Image(systemName: "minus")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
