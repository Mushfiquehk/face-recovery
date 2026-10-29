import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \FaceScan.capturedAt, order: .reverse) private var scans: [FaceScan]
    @Query(sort: \JournalEntry.dayStart) private var journalEntries: [JournalEntry]
    @State private var isBackfilling = false
    @State private var isExporting = false

    private var days: [DayEntry] { DayHistory.build(from: scans) }
    private var histogram: ScoreHistogram { ScoreHistogram(days: days) }
    private var weeks: ScoreWeeks { ScoreWeeks(days: days) }
    private var journaledDays: Set<Date> { Set(journalEntries.map(\.dayStart)) }

    /// Days grouped by calendar month, newest first, so a long history can be scanned by month.
    private var months: [(month: Date, days: [DayEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: days) {
            calendar.dateInterval(of: .month, for: $0.dayStart)?.start ?? $0.dayStart
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView {
                        Label("No scans yet", systemImage: "face.smiling")
                    } description: {
                        Text("Take a scan on the Scan tab, or add past photos to build your usual face straight away.")
                    } actions: {
                        Button {
                            isBackfilling = true
                        } label: {
                            Label("Add past photos", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            HistoryChartsView(histogram: histogram, weeks: weeks)
                        }

                        // Days with no Face Scan are absent rather than interpolated: a day
                        // with no observation has no Daily Sleep Prediction.
                        ForEach(months, id: \.month) { month in
                            Section(month.month.formatted(.dateTime.month(.wide).year())) {
                                ForEach(month.days) { day in
                                    NavigationLink(value: day.dayStart) {
                                        DayRow(day: day, hasJournal: journaledDays.contains(day.dayStart))
                                    }
                                }
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
                ToolbarItem(placement: .topBarTrailing) {
                    // Named actions in a menu rather than two bare icons, which are easy to
                    // misread.
                    Menu {
                        Button("Add past photos", systemImage: "photo.on.rectangle") {
                            isBackfilling = true
                        }
                        Button("Export all data", systemImage: "square.and.arrow.up.on.square") {
                            isExporting = true
                        }
                        .disabled(scans.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isBackfilling) { BackfillView() }
            .sheet(isPresented: $isExporting) {
                ExportView(scans: scans, journalEntries: journalEntries)
            }
        }
    }
}

private struct DayRow: View {
    let day: DayEntry
    let hasJournal: Bool

    private var prediction: SleepPrediction? { day.dailyPrediction }

    var body: some View {
        HStack(spacing: 14) {
            if let image = PhotoStore.thumbnail(day.canonical.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(day.dayStart.formatted(.dateTime.weekday(.wide).day()))
                    .font(.headline)

                Text(status.text)
                    .font(.subheadline)
                    .foregroundStyle(status.color)

                if !marks.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(marks, id: \.text) { mark in
                            Label(mark.text, systemImage: mark.symbol)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 8)

            ScoreBadge(value: prediction.flatMap { $0.isBaselineForming ? nil : $0.value })
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var status: (text: String, color: Color) {
        guard let prediction else {
            return day.canonical.isMeasured
                ? ("Photo did not count", Palette.caution)
                : ("Not read yet", Palette.caution)
        }
        if prediction.isBaselineForming { return ("Learning your usual face", .secondary) }
        let band = SleepBand(value: prediction.value)
        return (band.label, band.color)
    }

    private var marks: [(text: String, symbol: String)] {
        var marks: [(String, String)] = []
        if hasJournal { marks.append(("Journal", "book.closed")) }
        if day.hasMultipleScans { marks.append(("\(day.allScans.count) scans", "square.stack")) }
        if day.canonical.isBackfilled { marks.append(("Past photo", "clock.arrow.circlepath")) }
        if day.canonical.isDateAdjusted { marks.append(("Date changed", "calendar.badge.exclamationmark")) }
        return marks
    }
}

/// A small ring with the reading inside, the same shape and colours as the big one on a day, so
/// a row can be read at a glance. An empty grey ring with a dash means no reading.
private struct ScoreBadge: View {
    let value: Int?

    var body: some View {
        let color = value.map { SleepBand(value: $0).color } ?? .secondary
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 4)
            if let value {
                Circle()
                    .trim(from: 0, to: Double(value) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(value.map(String.init) ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: 50, height: 50)
        .accessibilityLabel(value.map { "Sleep reading \($0)" } ?? "No sleep reading")
    }
}
