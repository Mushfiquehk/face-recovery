import SwiftUI

/// The top of a day: the Sleep Prediction as a ring, what band it falls in, and one plain line
/// on what it means. Shared by the scan result and the day detail so a day reads the same way
/// wherever it is opened.
struct PredictionHeader: View {
    let scan: FaceScan
    /// Nil for an unmeasured or Unusable Scan, which get no Sleep Prediction.
    let prediction: SleepPrediction?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                PredictionRing(value: shownValue, color: band?.color ?? .secondary)
                    .frame(width: 200, height: 200)

                VStack(spacing: 0) {
                    Text(shownValue.map { "\($0)" } ?? "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(shownValue == nil ? "no reading" : "out of 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // Capped so the words stay inside the ring at the largest text sizes; the
                // number is already large and the band below carries the meaning in full size.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shownValue.map { "Sleep reading \($0) out of 100" } ?? "No sleep reading")

            VStack(spacing: 6) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(band?.color ?? .primary)
                Text(caption)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            HStack(spacing: 8) {
                if let image = PhotoStore.thumbnail(scan.photoFilename, maxPixelSize: 120) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }
                Text(scan.capturedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// While Baseline Forming the value is only the average night, so the ring stays empty
    /// rather than look like a reading of this photo.
    private var shownValue: Int? {
        guard let prediction, !prediction.isBaselineForming else { return nil }
        return prediction.value
    }

    private var band: SleepBand? { shownValue.map(SleepBand.init(value:)) }

    private var headline: String {
        guard let prediction else {
            return scan.isMeasured ? "This photo did not count" : "Not read yet"
        }
        return prediction.isBaselineForming ? "Learning your usual face" : SleepBand(value: prediction.value).label
    }

    private var caption: String {
        guard let prediction else {
            return scan.isMeasured
                ? "The photo check below says what to change. Your photo is kept."
                : "Tap Read this scan below."
        }
        let average = Int(prediction.startingValue.rounded())
        if prediction.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            let have = prediction.baseline.sampleCount
            return "\(have) of \(needed) clear morning scans so far. After that, each photo is compared with your usual face. Your average night is \(average)."
        }
        let difference = prediction.value - average
        let comparison = switch difference {
        case 0: "Right at your average night"
        case 1...: "\(difference) above your average night of \(average)"
        default: "\(-difference) below your average night of \(average)"
        }
        return "\(comparison). Predicted WHOOP sleep performance, read from your face."
    }
}
