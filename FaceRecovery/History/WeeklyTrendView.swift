import SwiftUI
import Charts

/// This week and last week as two line plots, for the "Weekly" tab of History.
///
/// Built to be read at a glance by older users: a plain sentence and an arrow say whether the
/// week is up or down before any chart is read; each plot is one line with a filled circle per
/// scored day and its number written beside it; the background is shaded green, yellow and red
/// by band, and the band is also written in the legend, so colour is never the only cue. Both
/// plots share one scale, so a higher line really is a better week.
struct WeeklyTrendView: View {
    let weeks: ScoreWeeks

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your week at a glance")
                .font(.title3.weight(.semibold))

            comparison

            if weeks.hasScores {
                WeekPlotCard(week: weeks.thisWeek, weeks: weeks)
                WeekPlotCard(week: weeks.lastWeek, weeks: weeks)
                BandLegend()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Comparison

    private var comparison: some View {
        HStack(alignment: .center, spacing: 14) {
            if weeks.hasScores {
                Image(systemName: trendSymbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(trendColor)
                    .frame(width: 48)
                    .accessibilityHidden(true)
            }
            Text(weeks.summary)
                .font(.body)
                .foregroundStyle(weeks.hasScores ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var trendSymbol: String {
        switch weeks.trend {
        case .up: "arrow.up.right.circle.fill"
        case .down: "arrow.down.right.circle.fill"
        case .steady: "equal.circle.fill"
        case nil: "circle.dotted"
        }
    }

    private var trendColor: Color {
        switch weeks.trend {
        case .up: .green
        case .down: .orange
        case .steady, nil: .secondary
        }
    }
}

// MARK: - One week

private struct WeekPlotCard: View {
    let week: ScoreWeeks.Week
    let weeks: ScoreWeeks

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var normal: Int { Int(ScoreTuning.default.atBaselineScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if week.points.isEmpty {
                Text(week.title == "This week" ? "No scores yet this week." : "No scores from last week.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            chart
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : 190)
                .opacity(week.points.isEmpty ? 0.45 : 1)
                .accessibilityHidden(true)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(week.title)
                    .font(.headline)
                Text((week.start..<week.end).formatted(.interval.month(.abbreviated).day()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let average = week.average {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(average)")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("average")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessibilityText: String {
        guard !week.points.isEmpty else { return "\(week.title): no scores." }
        let days = week.points
            .map { "\($0.dayStart.formatted(.dateTime.weekday(.wide))) \($0.score)" }
            .joined(separator: ", ")
        return "\(week.title), average \(week.average ?? 0). \(days)."
    }

    // MARK: Chart

    /// Plotted at midday so each point sits in the middle of its day rather than on the line
    /// between two days.
    private func midday(_ day: Date) -> Date { day.addingTimeInterval(12 * 3600) }

    private var xDomain: ClosedRange<Date> {
        week.start...week.start.addingTimeInterval(7 * 24 * 3600)
    }

    private var yDomain: ClosedRange<Int> { weeks.yDomain }

    /// Green, yellow and red zones behind the line, cut at the band edges.
    private var zones: [(range: ClosedRange<Int>, color: Color)] {
        let edges = [(0, 33, RecoveryBand.low), (34, 66, .medium), (67, 100, .high)]
        return edges.compactMap { low, high, band in
            let lower = max(low, yDomain.lowerBound)
            let upper = min(high + 1, yDomain.upperBound)
            guard lower < upper else { return nil }
            return (lower...upper, band.color)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                RectangleMark(
                    yStart: .value("From", zone.range.lowerBound),
                    yEnd: .value("To", zone.range.upperBound)
                )
                .foregroundStyle(zone.color.opacity(0.12))
            }

            RuleMark(y: .value("Normal", normal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("Your normal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

            // One line per run of consecutive days, so a day with no scan is a visible gap.
            ForEach(Array(week.runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    LineMark(
                        x: .value("Day", midday(point.dayStart)),
                        y: .value("Score", point.score),
                        series: .value("Run", index)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.primary.opacity(0.55))
                }
            }

            ForEach(week.points) { point in
                PointMark(
                    x: .value("Day", midday(point.dayStart)),
                    y: .value("Score", point.score)
                )
                .symbol(.circle)
                .symbolSize(dynamicTypeSize.isAccessibilitySize ? 260 : 170)
                .foregroundStyle(RecoveryBand(value: point.score).color)
                .annotation(position: .top, spacing: 4) {
                    Text("\(point.score)")
                        .font(.callout.weight(.bold).monospacedDigit())
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            // Letters only at large text sizes: seven day names would run into each other.
            AxisMarks(values: week.days.map(midday)) { _ in
                AxisValueLabel(format: dayFormat)
                    .font(.callout)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: weeks.yTicks) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.25))
                if let score = value.as(Int.self) {
                    AxisValueLabel("\(score)").font(.callout)
                }
            }
        }
        .chartXAxisLabel("Day of the week", alignment: .center)
        .chartYAxisLabel("Recovery Score", position: .leading)
    }

    private var dayFormat: Date.FormatStyle {
        dynamicTypeSize.isAccessibilitySize
            ? .dateTime.weekday(.narrow)
            : .dateTime.weekday(.abbreviated)
    }
}

// MARK: - Legend

/// What the three background colours mean, in words as well as colour.
private struct BandLegend: View {
    private let rows: [(band: RecoveryBand, range: String)] = [
        (.high, "67 and up"),
        (.medium, "34 to 66"),
        (.low, "33 and below"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.range) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(row.band.color)
                        .frame(width: 16, height: 16)
                    Text("\(row.band.label): \(row.range)")
                        .font(.callout)
                }
            }
            Text("The dotted line is your normal, 70. A line that sits higher means a better week.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The History header: the histogram and the weekly lines behind a two-way switch.
struct HistoryChartsView: View {
    let histogram: ScoreHistogram
    let weeks: ScoreWeeks

    private enum Tab: String, CaseIterable, Identifiable {
        case spread = "Spread"
        case weekly = "Weekly"
        var id: Self { self }
    }

    @State private var tab: Tab = .spread

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Chart", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .spread: ScoreHistogramView(histogram: histogram)
            case .weekly: WeeklyTrendView(weeks: weeks)
            }
        }
    }
}
