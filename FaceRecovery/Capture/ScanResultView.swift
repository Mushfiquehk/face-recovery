import SwiftUI

/// The screen shown straight after a scan is scored: the Recovery Score as a headline ring,
/// then the Signals and Capture Quality that explain it.
struct ScanResultView: View {
    let scan: FaceScan
    /// Nil for an Unusable Scan, which is stored but never scored.
    let score: RecoveryScore?
    var onTakeAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                    .padding(.top, 8)

                if let score, !score.isBaselineForming, let mover = biggestMover(score) {
                    moverCard(signal: mover, deviation: score[deviation: mover])
                }

                if let signals = scan.signals {
                    card(title: "Signals", subtitle: score?.isBaselineForming == false ? "vs your normal" : nil) {
                        ScanReadingView(signals: signals, score: score)
                    }
                }

                if let quality = scan.quality {
                    card(title: "Capture quality") {
                        CaptureQualityView(quality: quality)
                    }
                }

                Button("Take another", action: onTakeAnother)
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
                RecoveryRing(value: score?.value, color: band?.color ?? .secondary)
                    .frame(width: 210, height: 210)

                VStack(spacing: 2) {
                    Text(score.map { "\($0.value)" } ?? "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("RECOVERY")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(score.map { "Recovery Score \($0.value)" } ?? "No Recovery Score")

            VStack(spacing: 4) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(band?.color ?? .primary)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                if let image = PhotoStore.load(scan.photoFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                }
                Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var band: RecoveryBand? { score.map { RecoveryBand(value: $0.value) } }

    private var headline: String {
        guard let score else { return "Unusable Scan" }
        return score.isBaselineForming ? "Baseline forming" : RecoveryBand(value: score.value).label
    }

    private var caption: String {
        guard let score else {
            return "Stored in full, but not scored so lighting or framing is never read as recovery."
        }
        if score.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            return "Read from Absolute Signals until you have \(needed) qualifying scans."
        }
        let n = score.baseline.sampleCount
        return "Against your Personal Baseline of \(n) scan\(n == 1 ? "" : "s"). 70 is your normal."
    }

    // MARK: Details

    /// The Signal furthest from baseline, if any moved enough to be worth calling out.
    private func biggestMover(_ score: RecoveryScore) -> Signal? {
        Signal.allCases
            .max { abs(score[deviation: $0]) < abs(score[deviation: $1]) }
            .flatMap { abs(score[deviation: $0]) >= 5 ? $0 : nil }
    }

    private func moverCard(signal: Signal, deviation: Double) -> some View {
        let worse = deviation > 0
        return HStack(spacing: 12) {
            Image(systemName: worse ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(worse ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Biggest change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(signal.displayName) \(worse ? "higher" : "lower") than normal")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            Text(worse ? "+\(Int(deviation.rounded()))" : "\(Int(deviation.rounded()))")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(worse ? .orange : .green)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func card<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Green / yellow / red bands for a Recovery Score. Display only: the bands never feed back
/// into the arithmetic.
enum RecoveryBand {
    case high, medium, low

    init(value: Int) {
        switch value {
        case 67...: self = .high
        case 34...: self = .medium
        default: self = .low
        }
    }

    var color: Color {
        switch self {
        case .high: .green
        case .medium: .yellow
        case .low: .red
        }
    }

    var label: String {
        switch self {
        case .high: "Looking recovered"
        case .medium: "Looking a little worn"
        case .low: "Looking fatigued"
        }
    }
}

/// A 0-100 progress ring. A nil value draws the empty track only.
struct RecoveryRing: View {
    let value: Int?
    let color: Color
    var lineWidth: CGFloat = 16

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                progress = Double(value ?? 0) / 100
            }
        }
    }
}
