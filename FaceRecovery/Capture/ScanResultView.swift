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
                hero
                    .padding(.top, 8)

                AudioReportButton(sentences: DailyReport.sentences(
                    dayStart: scan.dayStart,
                    isMeasured: scan.isMeasured,
                    prediction: prediction
                ))

                if let prediction, !prediction.isBaselineForming {
                    TitledCard(title: "Why this number") {
                        RegionPhoto(scan: scan, highlighted: selected)
                            .frame(maxHeight: 320)
                        ContributionsView(prediction: prediction, selected: $selected)
                        SignalBreakdownLink(scan: scan, prediction: prediction)
                            .buttonStyle(.bordered)
                    }
                }

                if let measurement = scan.measurement {
                    TitledCard(title: "Photo check") {
                        PhotoCheckView(measurement: measurement)
                    }
                }

                TitledCard(title: "Journal") {
                    JournalPanel(dayStart: scan.dayStart)
                }

                Button(action: onTakeAnother) {
                    Text("Take another")
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

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                PredictionRing(value: prediction?.value, color: band?.color ?? .secondary)
                    .frame(width: 210, height: 210)

                VStack(spacing: 2) {
                    Text(prediction.map { "\($0.value)" } ?? "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("SLEEP")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(prediction.map { "Sleep Prediction \($0.value)" } ?? "No Sleep Prediction")

            VStack(spacing: 6) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(band?.color ?? .primary)
                    .multilineTextAlignment(.center)
                Text(caption)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            if prediction?.isBaselineForming ?? true, let image = PhotoStore.load(scan.photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
            Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var band: SleepBand? {
        guard let prediction, !prediction.isBaselineForming else { return nil }
        return SleepBand(value: prediction.value)
    }

    private var headline: String {
        guard let prediction else { return "This photo did not count" }
        return prediction.isBaselineForming ? "Learning your usual face" : SleepBand(value: prediction.value).label
    }

    private var caption: String {
        guard let prediction else {
            return "See the photo check below for what to change. Your photo is kept."
        }
        let average = Int(prediction.startingValue.rounded())
        if prediction.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            let have = prediction.baseline.sampleCount
            return "Your average night is \(average). After \(needed) clear morning scans (you have \(have)), each photo is compared with your usual face. Until then this shows your average."
        }
        return "Predicted WHOOP sleep performance, from your face. Your average night is \(average)."
    }
}

/// A rounded card with a small capitalised title, on a grouped background.
struct TitledCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.callout.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
