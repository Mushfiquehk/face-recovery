import SwiftUI

/// A Sleep Prediction taken apart: the starting value, one line per Signal saying how it moved the
/// number, and the result. Shared by the capture result and the day detail so a Contribution
/// always reads the same way. Written for older users: plain words, large type, no jargon.
struct ContributionsView: View {
    let prediction: SleepPrediction
    /// The Signal whose region is outlined on the photo; tapping a line selects it.
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            totalRow(title: "Your average night", value: prediction.startingValue)

            ForEach(prediction.contributions) { contribution in
                Button {
                    selected = selected == contribution.id ? nil : contribution.id
                } label: {
                    ContributionRow(contribution: contribution, isSelected: selected == contribution.id)
                }
                .buttonStyle(.plain)
            }

            Divider()
            totalRow(title: "Today", value: Double(prediction.value))
            if prediction.isCapped {
                Text("The changes add up to \(Int(prediction.uncappedValue.rounded())), shown as \(prediction.value) because the scale runs from 0 to 100.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        let n = prediction.baseline.sampleCount
        var text = "Each line is how much one thing in your photo moved the number, compared with your usual face over your last \(n) clear morning\(n == 1 ? "" : "s"). Tap a line to see where it was measured."
        if SleepModel.bundled.nightsUsed == 0 {
            text += " The amounts come from research on how tired faces look; they will be tuned to your own WHOOP nights once there are enough clear mornings."
        }
        return text
    }

    private func totalRow(title: String, value: Double) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text("\(Int(value.rounded()))")
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ContributionRow: View {
    let contribution: Contribution
    let isSelected: Bool

    private var rounded: Int { Int(contribution.points.rounded()) }
    private var colour: Color { rounded > 0 ? .green : rounded < 0 ? .orange : .secondary }
    private var pointsText: String { rounded > 0 ? "+\(rounded)" : rounded < 0 ? "−\(-rounded)" : "0" }

    private var description: String {
        guard !contribution.isSteady else { return "About the same as usual" }
        let words = contribution.words
        return words.prefix(1).uppercased() + words.dropFirst() + " than usual"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contribution.signal.name)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(pointsText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(colour)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(10)
        .frame(minHeight: 56)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contribution.signal.name). \(description). \(pointsText) points.")
        .accessibilityHint("Shows where on your photo this was measured.")
    }
}

/// The photo with the area behind one Signal outlined, so a Contribution points at a real place
/// on the face rather than at an abstract number.
struct RegionPhoto: View {
    let scan: FaceScan
    /// Signal id to outline; nil outlines nothing.
    let highlighted: String?

    var body: some View {
        if let image = PhotoStore.load(scan.photoFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if let highlighted, let regions = scan.measurement?.measurement?.regions {
                        GeometryReader { geometry in
                            outline(Self.regionKeys(for: highlighted).compactMap { regions[$0] }, in: geometry.size)
                                .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                                .shadow(color: .black.opacity(0.6), radius: 2)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(highlighted == nil ? "Your photo" : "Your photo, with the measured area outlined")
        }
    }

    private func outline(_ polygons: [[[Double]]], in size: CGSize) -> Path {
        Path { path in
            for polygon in polygons {
                guard let first = polygon.first, first.count == 2 else { continue }
                path.move(to: CGPoint(x: first[0] * size.width, y: first[1] * size.height))
                for point in polygon.dropFirst() where point.count == 2 {
                    path.addLine(to: CGPoint(x: point[0] * size.width, y: point[1] * size.height))
                }
                path.closeSubpath()
            }
        }
    }

    /// Which measured regions each Signal is read from (`FaceMeasurement.regions`).
    static func regionKeys(for signal: String) -> [String] {
        switch signal {
        case "under_eye_shadow", "under_eye_contrast", "under_eye_blue":
            ["under_eye_left", "under_eye_right", "cheek_left", "cheek_right"]
        case "sclera_vs_skin_redness":
            ["eye_left", "eye_right", "cheek_left", "cheek_right"]
        case "sclera_redness", "eye_aperture", "eye_height", "eye_opening_edges", "brow_gap":
            ["eye_left", "eye_right"]
        case "skin_chroma":
            ["cheek_left", "cheek_right"]
        case "mouth_corner_droop":
            ["mouth"]
        default:
            []
        }
    }
}

/// Capture Quality in words a user can act on: whether the photo was clear enough to count,
/// and if not, what to change next time.
struct PhotoCheckView: View {
    let measurement: ScanMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if measurement.isUsable {
                Label("Clear photo", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Good light, facing the camera, no glasses.")
                    .font(.body)
            } else {
                Label("This photo did not count", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(measurement.problems, id: \.self) { problem in
                    Text("• \(problem)").font(.body)
                }
                Text("It is kept, but left out of your usual face and your trends so the light or the angle is never read as a bad night.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let quality = measurement.measurement?.quality {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Brightness", value: "\(Int(quality.brightness.rounded())) of 100")
                        LabeledContent("Sharpness", value: "\(Int(quality.sharpness.rounded()))")
                        LabeledContent("Head turned", value: "\(Int(abs(quality.yawDegrees).rounded()))°")
                        LabeledContent("Head tilted", value: "\(Int(abs(quality.rollDegrees).rounded()))°")
                        LabeledContent("Glasses score", value: String(format: "%.1f", quality.glassesScore))
                        LabeledContent("Measurement", value: measurement.version)
                    }
                    .font(.callout.monospacedDigit())
                    .padding(.top, 6)
                }
                .font(.body)
            }
        }
    }
}

/// WHOOP's own Sleep Performance bands, so a Sleep Prediction reads like the number it estimates.
/// Display only: the bands never feed back into the arithmetic.
enum SleepBand {
    case optimal, sufficient, poor

    init(value: Int) {
        switch value {
        case 85...: self = .optimal
        case 70...: self = .sufficient
        default: self = .poor
        }
    }

    var color: Color {
        switch self {
        case .optimal: .green
        case .sufficient: .yellow
        case .poor: .red
        }
    }

    var label: String {
        switch self {
        case .optimal: "Looks well slept"
        case .sufficient: "Looks a little short on sleep"
        case .poor: "Looks short on sleep"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .optimal: 85...100
        case .sufficient: 70...84
        case .poor: 0...69
        }
    }
}

/// A 0-100 progress ring. A nil value draws the empty track only.
struct PredictionRing: View {
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
