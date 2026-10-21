import SwiftUI
import Charts

/// One bar per scored day over the last two weeks, for the "Day by day" tab of History.
///
/// Same rules as the histogram, for older users: a plain sentence first, system text sizes,
/// one colour with the latest day marked by a darker bar and a number rather than by colour
/// alone, and a faint line where the user's own normal sits.
struct ScoreTrendView: View {
    let trend: ScoreTrend

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var normal: Int { Int(ScoreTuning.default.atBaselineScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your days, one by one")
                .font(.title3.weight(.semibold))

            Text(trend.summary)
                .font(.body)
                .foregroundStyle(trend.points.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if !trend.points.isEmpty {
                chart
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 320 : 200)
                    .accessibilityHidden(true)

                Text("Each bar is one day. The taller the bar, the better the score. The dark bar is your latest day, and the dotted line is your normal, \(normal).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func isLatest(_ point: ScoreTrend.Point) -> Bool { point == trend.latest }

    private func barColor(for point: ScoreTrend.Point) -> Color {
        isLatest(point) ? .accentColor : .accentColor.opacity(0.4)
    }

    private var xAxisStride: Int { dynamicTypeSize.isAccessibilitySize ? 7 : 3 }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Normal", normal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(Color.secondary)

            ForEach(trend.points) { point in
                BarMark(
                    x: .value("Day", point.dayStart, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(barColor(for: point))
                .annotation(position: .top) {
                    // Only the latest day is labelled, never every bar.
                    Text(isLatest(point) ? "\(point.score)" : "")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            // Few labels at large text sizes: a date for every bar would run together.
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.callout)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                if let score = value.as(Int.self) {
                    AxisValueLabel("\(score)").font(.callout)
                }
            }
        }
        .chartYAxisLabel("Recovery Score", position: .leading)
    }
}

/// The History header: the histogram and the day-by-day bars behind a two-way switch.
struct HistoryChartsView: View {
    let histogram: ScoreHistogram
    let trend: ScoreTrend

    private enum Chart: String, CaseIterable, Identifiable {
        case spread = "Spread"
        case dayByDay = "Day by day"
        var id: Self { self }
    }

    @State private var chart: Chart = .spread

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Chart", selection: $chart) {
                ForEach(Chart.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch chart {
            case .spread: ScoreHistogramView(histogram: histogram)
            case .dayByDay: ScoreTrendView(trend: trend)
            }
        }
    }
}
