import SwiftUI

/// Shows one scan's Absolute Signals, with deviation from the Personal Baseline when there is
/// one. Shared by the capture result and the day detail so a Signal always reads the same way.
struct ScanReadingView: View {
    let signals: SignalSet
    /// Nil while Baseline Forming or when the scan is not being read against a baseline.
    var score: RecoveryScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Signal.allCases) { signal in
                SignalRow(
                    name: signal.displayName,
                    value: signals[signal],
                    deviation: score.map { $0[deviation: signal] }
                )
            }

            Divider()

            // Kept visually apart because it is not one of the five Signals and is deliberately
            // excluded from the Recovery Score (ADR 0002).
            SignalRow(
                name: "Holistic tiredness",
                value: signals.holisticTiredness,
                deviation: score?.holisticDeviation
            )
            Text("Rated and baselined, but excluded from the Recovery Score so the decomposed Signals and the holistic judgement can be tested separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SignalRow: View {
    let name: String
    let value: Int
    /// Positive means more pronounced than this user's normal.
    var deviation: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.subheadline)
                Spacer()
                Text("\(value)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                if let deviation, abs(deviation) >= 0.5 {
                    Text(deviation > 0 ? "+\(Int(deviation.rounded()))" : "\(Int(deviation.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(deviation > 0 ? .orange : .green)
                }
            }
            ProgressView(value: Double(value), total: 100)
                .tint(.secondary)
        }
    }
}

/// Capture Quality is about the photograph, not the face. Surfacing it next to the Signals is
/// what stops a dark morning being read as a bad night.
struct CaptureQualityView: View {
    let quality: CaptureQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Lighting", value: "\(quality.lighting)")
            LabeledContent("Sharpness", value: "\(quality.sharpness)")
            LabeledContent("Face fully visible", value: quality.faceFullyVisible ? "Yes" : "No")

            if quality.isUsable {
                Label("Usable", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                Label("Unusable Scan", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                ForEach(quality.failureReasons, id: \.self) { reason in
                    Text("• \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Stored in full, but excluded from your Personal Baseline and from trends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}
