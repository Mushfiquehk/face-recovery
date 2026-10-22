import SwiftUI
import Charts

/// This week and last week on one set of axes, for the "Weekly" tab of History.
///
/// Built to be read at a glance by older users: a plain sentence and an arrow say whether the
/// week is up or down before any chart is read; both weeks sit on the same days of the week, so
/// the gap between the two lines is the answer; each week is one line with a filled circle per
/// scored day. This week is the bold coloured line with its numbers written above each circle,
/// last week is the thinner grey line with its numbers below. The two are told apart by weight
/// and label as well as colour. The background is shaded green, yellow and red by band, and the
/// bands are written in the legend, so colour is never the only cue.
struct WeeklyTrendView: View {
    let weeks: ScoreWeeks

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your week at a glance")
                .font(.title3.weight(.semibold))

            comparison

            if weeks.hasScores {
                WeekKey(weeks: weeks)
                CombinedWeekChart(weeks: weeks)
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

// MARK: - Look of each week

/// How each week is drawn, in one place so the key and the chart can never disagree.
private enum WeekStyle {
    case thisWeek, lastWeek

    var color: Color {
        switch self {
        case .thisWeek: .accentColor
        case .lastWeek: .gray
        }
    }

    var lineWidth: CGFloat { self == .thisWeek ? 4 : 2.5 }

    var keyMarkerSize: CGFloat { self == .thisWeek ? 16 : 12 }

    func markerSize(accessible: Bool) -> CGFloat {
        switch self {
        case .thisWeek: accessible ? 280 : 190
        case .lastWeek: accessible ? 170 : 110
        }
    }
}

// MARK: - Key

/// Says which line is which, with the dates and average of each, before the chart is read.
private struct WeekKey: View {
    let weeks: ScoreWeeks

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entry(weeks.thisWeek, style: .thisWeek)
            entry(weeks.lastWeek, style: .lastWeek)
        }
        .accessibilityElement(children: .combine)
    }

    private func entry(_ week: ScoreWeeks.Week, style: WeekStyle) -> some View {
        HStack(spacing: 12) {
            // A short sample of the line itself, so the key matches what is on the chart.
            ZStack {
                Capsule()
                    .fill(style.color)
                    .frame(width: 44, height: style.lineWidth)
                Circle()
                    .fill(style.color)
                    .frame(width: style.keyMarkerSize, height: style.keyMarkerSize)
            }
            .frame(width: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(week.title)
                    .font(.headline)
                Text((week.start..<week.end).formatted(.interval.month(.abbreviated).day()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let average = week.average {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(average)")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("average")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No scores")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Chart

private struct CombinedWeekChart: View {
    let weeks: ScoreWeeks

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var normal: Int { Int(SleepModel.bundled.startingValue.rounded()) }
    private var accessible: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        chart
            .frame(height: accessible ? 340 : 240)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [weeks.thisWeek, weeks.lastWeek].map { week in
            guard !week.points.isEmpty else { return "\(week.title): no scores." }
            let days = week.points
                .map { "\($0.dayStart.formatted(.dateTime.weekday(.wide))) \($0.score)" }
                .joined(separator: ", ")
            return "\(week.title), average \(week.average ?? 0). \(days)."
        }
        .joined(separator: " ")
    }

    // MARK: Positions

    /// Plotted at midday so each point sits in the middle of its day rather than on the line
    /// between two days.
    private func midday(_ day: Date) -> Date { day.addingTimeInterval(12 * 3600) }

    /// Last week is drawn on this week's days: its first day sits over this week's first day,
    /// and so on, so the two lines can be compared day for day.
    private func position(of point: ScoreWeeks.Point, in week: ScoreWeeks.Week) -> Date {
        let index = week.days.firstIndex(of: point.dayStart) ?? 0
        return midday(weeks.thisWeek.days[index])
    }

    private var xDomain: ClosedRange<Date> {
        let start = weeks.thisWeek.start
        return start...start.addingTimeInterval(7 * 24 * 3600)
    }

    private var yDomain: ClosedRange<Int> { weeks.yDomain }

    /// Green, yellow and red zones behind the lines, cut at the band edges.
    private var zones: [(range: ClosedRange<Int>, color: Color)] {
        let bands: [SleepBand] = [.poor, .sufficient, .optimal]
        return bands.compactMap { band in
            let lower = max(band.range.lowerBound, yDomain.lowerBound)
            let upper = min(band.range.upperBound + 1, yDomain.upperBound)
            guard lower < upper else { return nil }
            return (lower...upper, band.color)
        }
    }

    // MARK: Marks

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

            // Last week first so this week is drawn on top of it where they cross.
            marks(for: weeks.lastWeek, style: .lastWeek, label: .bottom)
            marks(for: weeks.thisWeek, style: .thisWeek, label: .top)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            // Letters only at large text sizes: seven day names would run into each other.
            AxisMarks(values: weeks.thisWeek.days.map(midday)) { _ in
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
        .chartYAxisLabel("Sleep Prediction", position: .leading)
    }

    /// One line per run of consecutive days, so a day with no scan is a visible gap, then a
    /// solid circle on every scored day with its score written beside it.
    @ChartContentBuilder
    private func marks(for week: ScoreWeeks.Week, style: WeekStyle, label: AnnotationPosition) -> some ChartContent {
        ForEach(Array(week.runs.enumerated()), id: \.offset) { index, run in
            ForEach(run) { point in
                LineMark(
                    x: .value("Day", position(of: point, in: week)),
                    y: .value("Score", point.score),
                    series: .value("Run", "\(week.title)-\(index)")
                )
                .lineStyle(StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round))
                .foregroundStyle(style.color)
            }
        }

        ForEach(week.points) { point in
            PointMark(
                x: .value("Day", position(of: point, in: week)),
                y: .value("Score", point.score)
            )
            .symbol(.circle)
            .symbolSize(style.markerSize(accessible: accessible))
            .foregroundStyle(style.color)
            .annotation(position: label, spacing: 4) {
                Text("\(point.score)")
                    .font(style == .thisWeek
                        ? .callout.weight(.bold).monospacedDigit()
                        : .caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(style == .thisWeek ? Color.primary : Color.secondary)
            }
        }
    }

    private var dayFormat: Date.FormatStyle {
        accessible ? .dateTime.weekday(.narrow) : .dateTime.weekday(.abbreviated)
    }
}

// MARK: - Legend

/// What the three background colours mean, in words as well as colour.
private struct BandLegend: View {
    private let rows: [(band: SleepBand, range: String)] = [
        (.optimal, "85 and up"),
        (.sufficient, "70 to 84"),
        (.poor, "69 and below"),
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
            Text("The dotted line is your average night, \(Int(SleepModel.bundled.startingValue.rounded())). A line that sits higher means a better-slept week.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The History header: the weekly lines and the histogram behind a two-way switch. Weekly comes
/// first and is what opens.
struct HistoryChartsView: View {
    let histogram: ScoreHistogram
    let weeks: ScoreWeeks

    private enum Tab: String, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case spread = "Spread"
        var id: Self { self }
    }

    @State private var tab: Tab = .weekly

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Chart", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .weekly: WeeklyTrendView(weeks: weeks)
            case .spread: ScoreHistogramView(histogram: histogram)
            }
        }
    }
}
