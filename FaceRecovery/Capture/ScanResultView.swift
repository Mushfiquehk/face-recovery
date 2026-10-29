import SwiftUI

/// The screen shown straight after a scan is measured: the Sleep Prediction as a headline ring,
/// then every Contribution that explains it, each pointing at the part of the photo it came from.
struct ScanResultView: View {
    let scan: FaceScan
    /// Nil for an Unusable Scan, which is stored but gets no Sleep Prediction.
    let prediction: SleepPrediction?
    var onTakeAnother: () -> Void

    @State private var selected: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PredictionHeader(scan: scan, prediction: prediction)

                DayActions(dayStart: scan.dayStart, scan: scan, prediction: prediction)

                // An Unusable Scan is explained by its photo check, so that comes first.
                if let measurement = scan.measurement, !measurement.isUsable {
                    TitledCard(title: "Photo check") {
                        PhotoCheckView(measurement: measurement)
                    }
                }

                if let prediction, !prediction.isBaselineForming {
                    TitledCard(title: "Why this number") {
                        RegionPhoto(scan: scan, highlighted: selected)
                            .frame(maxHeight: 320)
                        ContributionsView(prediction: prediction, selected: $selected)
                        SignalBreakdownLink(scan: scan, prediction: prediction)
                            .buttonStyle(.bordered)
                    }
                }

                TitledCard(title: "Journal") {
                    JournalPanel(dayStart: scan.dayStart)
                }

                if let measurement = scan.measurement, measurement.isUsable {
                    TitledCard(title: "Photo check") {
                        PhotoCheckView(measurement: measurement)
                    }
                }

                Button(action: onTakeAnother) {
                    Label("Take another photo", systemImage: "camera")
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Listen and Share, side by side under a day's header, and stacked when large text leaves no
/// room. Share is left out while there is no real reading to share.
struct DayActions: View {
    let dayStart: Date
    let scan: FaceScan
    let prediction: SleepPrediction?

    private var shareable: SleepPrediction? {
        guard let prediction, !prediction.isBaselineForming else { return nil }
        return prediction
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(spacing: 12) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        AudioReportButton(sentences: DailyReport.sentences(
            dayStart: dayStart,
            isMeasured: scan.isMeasured,
            prediction: prediction
        ))
        if let shareable {
            ShareResultButton(dayStart: dayStart, scan: scan, prediction: shareable)
        }
    }
}

/// A rounded card with a heading, on a grouped background.
struct TitledCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
