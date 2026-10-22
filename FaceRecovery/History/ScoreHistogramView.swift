import SwiftUI
import Charts

/// The spread of Sleep Predictions across all measured days, for the top of History.
///
/// Built for older users: a plain sentence says what the shape means before any chart is read,
/// text sizes follow the system setting, and the chart is one colour with the latest day marked
/// by a darker bar and a label rather than by colour alone. The grid is faint and nothing else
/// competes with the bars.
struct ScoreHistogramView: View {
    let histogram: ScoreHistogram

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How your days have scored")
                .font(.title3.weight(.semibold))

            Text(histogram.summary)
                .font(.body)
                .foregroundStyle(histogram.totalDays == 0 ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if histogram.totalDays > 0 {
                chart
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 320 : 200)
                    .accessibilityHidden(true)

                Text("Each bar is a group of ten scores. The taller the bar, the more days landed there. The dark bar holds your latest day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func barColor(for bin: ScoreHistogram.Bin) -> Color {
        bin.lowerBound == histogram.latestBinLowerBound ? .accentColor : .accentColor.opacity(0.4)
    }

    private func isLabelled(_ bin: ScoreHistogram.Bin) -> Bool {
        guard bin.count > 0 else { return false }
        let isBusiest = bin.lowerBound == histogram.modalBin?.lowerBound
        let isLatest = bin.lowerBound == histogram.latestBinLowerBound
        return isBusiest || isLatest
    }

    private func countText(for bin: ScoreHistogram.Bin) -> String {
        isLabelled(bin) ? String(bin.count) : ""
    }

    private func bar(for bin: ScoreHistogram.Bin) -> some ChartContent {
        // Inset a fraction of a point each side so neighbouring bars read as separate bars.
        let from: PlottableValue<Double> = .value("From", Double(bin.lowerBound) + 0.25)
        let to: PlottableValue<Double> = .value("To", Double(bin.lowerBound + ScoreHistogram.binWidth) - 0.25)
        let zero: PlottableValue<Int> = .value("Zero", 0)
        let days: PlottableValue<Int> = .value("Days", bin.count)
        return RectangleMark(xStart: from, xEnd: to, yStart: zero, yEnd: days)
            .foregroundStyle(barColor(for: bin))
            .annotation(position: .top) {
                // Only the busiest bin and the latest bin are labelled, never every bar.
                Text(countText(for: bin))
                    .font(.callout.weight(.semibold))
            }
    }

    private var xAxisValues: [Double] {
        dynamicTypeSize.isAccessibilitySize ? [0, 50, 100] : [0, 20, 40, 60, 80, 100]
    }

    private var chart: some View {
        Chart {
            ForEach(histogram.bins) { bin in
                bar(for: bin)
            }
        }
        // A hair wider than 0...100: Charts hides a label that sits exactly on the domain edge.
        .chartXScale(domain: [-2.0, 102.0])
        .chartXAxis {
            // Three labels at large text sizes: five would run into each other.
            AxisMarks(values: xAxisValues) { value in
                // Charts clips a label at the plot edge, so the last one hangs inward from its tick.
                let isLast = value.as(Double.self) == 100
                AxisValueLabel(anchor: isLast ? .topTrailing : .top)
                    .font(.callout)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                // Whole days only: a half day is not a thing.
                if let days = value.as(Int.self) {
                    AxisValueLabel("\(days)").font(.callout)
                }
            }
        }
        .chartXAxisLabel("Sleep Prediction", alignment: .center)
        .chartYAxisLabel("Days", position: .leading)
    }
}
