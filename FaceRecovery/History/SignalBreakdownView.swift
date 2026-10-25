import SwiftUI

/// The long form of `ContributionsView`: every Signal measured on one Face Scan, each shown where
/// it was read on the photo, set against the Personal Baseline, with the arithmetic that turned
/// the difference into its Contribution. Reached from "Why this number" on the scan result and
/// the day detail. Written for older users: one card per Signal, plain words first, numbers last.
struct SignalBreakdownView: View {
    let scan: FaceScan
    let prediction: SleepPrediction

    @State private var image: UIImage?

    private var measurement: FaceMeasurement? { scan.measurement?.measurement }

    /// Measured on this scan but not part of the Sleep Model, so they moved nothing.
    private var unscored: [String] {
        let scored = Set(prediction.contributions.map(\.id))
        let measured = measurement?.signals ?? [:]
        return SignalGlossary.order.filter { measured[$0] != nil && !scored.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summary

                ForEach(prediction.contributions) { contribution in
                    SignalCard(
                        contribution: contribution,
                        image: image,
                        regions: measurement?.regions ?? [:],
                        range: SleepModel.bundled.contributionClamp
                    )
                }

                if !unscored.isEmpty {
                    unscoredCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("What your photo showed")
        .navigationBarTitleDisplayMode(.inline)
        .task { image = PhotoStore.load(scan.photoFilename) }
    }

    // MARK: Summary

    private var summary: some View {
        TitledCard(title: "How today's number was made") {
            totalRow(title: "Your average night", value: Int(prediction.startingValue.rounded()))
            totalRow(title: "Today", value: prediction.value)

            Text(summaryText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if SleepModel.bundled.nightsUsed == 0 {
                Text("The points for each part come from research on how tired faces look. They will be tuned to your own WHOOP nights once there are enough clear mornings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryText: String {
        let n = prediction.baseline.sampleCount
        let parts = prediction.contributions.count
        return "Your photo was compared with your usual face, taken from your last \(n) clear morning\(n == 1 ? "" : "s"). Below are the \(parts) parts of your face that count: what was measured, how far it was from usual, and how many points that moved the number."
    }

    private func totalRow(title: String, value: Int) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text("\(value)").font(.title2.weight(.bold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Unscored

    private var unscoredCard: some View {
        TitledCard(title: "Also measured") {
            Text("These are read from every photo and kept, but they are not part of the number yet, so they did not move it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(unscored, id: \.self) { id in
                VStack(alignment: .leading, spacing: 4) {
                    Text(SignalGlossary.name(id)).font(.body.weight(.semibold))
                    if let measures = SignalGlossary.measures(id) {
                        Text(measures)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 20) {
                        Text("Today \(SignalGlossary.format(measurement?.signals[id]))")
                        Text("Usual \(SignalGlossary.format(prediction.baseline.medians[id]))")
                    }
                    .font(.callout.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Opens the breakdown from a "Why this number" card. Callers style it to fit a List or a card.
struct SignalBreakdownLink: View {
    let scan: FaceScan
    let prediction: SleepPrediction

    var body: some View {
        NavigationLink {
            SignalBreakdownView(scan: scan, prediction: prediction)
        } label: {
            Label("See each part of your face", systemImage: "face.dashed")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .accessibilityHint("Shows what was measured on each part of your face and how it changed the number.")
    }
}

// MARK: - One Signal

private struct SignalCard: View {
    let contribution: Contribution
    let image: UIImage?
    let regions: [String: [[Double]]]
    /// The Sleep Model's clamp, in typical differences: the gauge runs this far either side.
    let range: Double

    private var signal: SleepModel.SignalWeight { contribution.signal }
    private var referenceKeys: [String] { SignalGlossary.referenceKeys(for: signal.id) }
    private var measuredPolygons: [[[Double]]] {
        RegionPhoto.regionKeys(for: signal.id).filter { !referenceKeys.contains($0) }.compactMap { regions[$0] }
    }
    private var referencePolygons: [[[Double]]] { referenceKeys.compactMap { regions[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(signal.name)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text(contribution.pointsText)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(contribution.colour)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(signal.name), \(contribution.pointsText) points")

            if let image, !measuredPolygons.isEmpty {
                RegionZoom(image: image, measured: measuredPolygons, reference: referencePolygons)
                    .frame(height: 180)
                    .accessibilityLabel("Close-up of your photo where this was measured")
                Text(referencePolygons.isEmpty
                     ? "Yellow line: where this was measured."
                     : "Yellow line: where this was measured. Dashed white line: your cheek, which it is compared with.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let measures = SignalGlossary.measures(signal.id) {
                Text(measures)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(contribution.summary)
                .font(.title3.weight(.semibold))

            DeviationGauge(contribution: contribution, range: range)

            Text(explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            arithmetic

            DisclosureGroup("The exact numbers") {
                exactNumbers
                    .padding(.top, 6)
            }
            .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Words

    private var weight: Double { abs(signal.weight) }

    private var explanation: String {
        guard weight > 0 else {
            return "The Sleep Model gives this no points at the moment, so it did not move the number."
        }
        let size = Self.decimal(abs(contribution.deviation))
        var sentences: [String] = []
        if contribution.isSteady {
            sentences.append("Today's change was \(size) of a normal day-to-day change, which is within your usual range.")
        } else {
            sentences.append("Today you looked \(contribution.words). The change was \(size) times a normal day-to-day change.")
        }
        if contribution.deviation != 0 {
            let direction = signal.weight * contribution.deviation > 0 ? "goes up" : "goes down"
            sentences.append("For each normal-sized change towards \(contribution.words), the number \(direction) by \(Self.amount(weight)) point\(weight == 1 ? "" : "s").")
        }
        if contribution.isClamped {
            let cap = Self.decimal(abs(contribution.countedDeviation))
            sentences.append("No single part of the face may count for more than \(cap) normal changes, so this counted as \(cap).")
        }
        return sentences.joined(separator: " ")
    }

    /// The sum written out with magnitudes only; the direction is in words, which reads more
    /// easily than a product of two negative numbers.
    private var arithmetic: some View {
        let counted = Self.decimal(abs(contribution.countedDeviation))
        let raw = Self.decimal(abs(contribution.points))
        let rounded = abs(contribution.roundedPoints)
        let outcome = switch contribution.roundedPoints {
        case 0: "no change"
        case 1...: "\(rounded) point\(rounded == 1 ? "" : "s") added"
        default: "\(rounded) point\(rounded == 1 ? "" : "s") taken off"
        }
        return Text("\(counted) × \(Self.amount(weight)) = \(raw), so \(outcome)")
            .font(.body.weight(.semibold).monospacedDigit())
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(contribution.colour.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("\(counted) times \(Self.amount(weight)) is \(raw), so \(outcome).")
    }

    private var exactNumbers: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Today", value: SignalGlossary.format(contribution.value))
            LabeledContent("Your usual", value: SignalGlossary.format(contribution.usual))
            LabeledContent("Difference", value: SignalGlossary.format(contribution.value - contribution.usual))
            LabeledContent("Normal day-to-day change", value: SignalGlossary.format(signal.typicalDeviation))
            LabeledContent("Normal changes away", value: Self.signed(contribution.deviation, digits: 2))
            if contribution.isClamped {
                LabeledContent("Counted as", value: Self.signed(contribution.countedDeviation, digits: 2))
            }
            LabeledContent("Points per normal change", value: Self.signed(signal.weight, digits: 1))
            LabeledContent("Points", value: Self.signed(contribution.points, digits: 1))
            LabeledContent("Measured as", value: signal.id)
        }
        .font(.callout.monospacedDigit())
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Whole numbers stay whole: "4", not "4.0".
    private static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func signed(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).sign(strategy: .always()))
    }
}

/// Where today sits against the usual: the centre mark is the Personal Baseline, the shaded band
/// is a change too small to mention, and the dot is today, in normal day-to-day changes. The two
/// ends are named in words, so the direction never depends on colour.
private struct DeviationGauge: View {
    let contribution: Contribution
    let range: Double

    @ScaledMetric private var labelHeight = 24.0
    private let dot = 26.0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let usable = width - dot
                let x = { (d: Double) in dot / 2 + usable * (min(max(d, -range), range) + range) / (2 * range) }
                let trackY = labelHeight + dot / 2 + 4
                let centre = x(0)
                let today = x(contribution.deviation)

                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(width: usable, height: 8)
                        .position(x: width / 2, y: trackY)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: x(0.5) - x(-0.5), height: 22)
                        .position(x: centre, y: trackY)
                    Capsule()
                        .fill(contribution.colour)
                        .frame(width: abs(today - centre), height: 8)
                        .position(x: (today + centre) / 2, y: trackY)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: dot)
                        .position(x: centre, y: trackY)
                    Circle()
                        .fill(contribution.colour)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 3))
                        .frame(width: dot, height: dot)
                        .position(x: today, y: trackY)
                    // Centred over the dot, unless that would push it past an edge at large
                    // text sizes; then it hugs that edge instead.
                    Text("Today")
                        .font(.callout.weight(.semibold))
                        .fixedSize()
                        .frame(width: width, alignment: today < width / 4 ? .leading : today > width * 3 / 4 ? .trailing : .center)
                        .offset(x: today < width / 4 || today > width * 3 / 4 ? 0 : today - width / 2)
                        .position(x: width / 2, y: labelHeight / 2)
                    Text("Usual")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: centre, y: trackY + dot / 2 + 4 + labelHeight / 2)
                }
            }
            .frame(height: 2 * labelHeight + dot + 8)

            HStack(alignment: .top) {
                Text("← " + Self.capitalised(contribution.signal.lowerMeans))
                Spacer(minLength: 16)
                Text(Self.capitalised(contribution.signal.higherMeans) + " →")
                    .multilineTextAlignment(.trailing)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let size = abs(contribution.deviation).formatted(.number.precision(.fractionLength(1)))
        return contribution.isSteady
            ? "Today was close to your usual, \(size) of a normal change."
            : "Today was \(size) normal changes towards \(contribution.words)."
    }

    private static func capitalised(_ words: String) -> String {
        words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// A close-up of the photo around one Signal's regions: the measured area outlined solid
/// yellow, and any patch it is compared against (the cheek) dashed white.
private struct RegionZoom: View {
    let image: UIImage
    let measured: [[[Double]]]
    let reference: [[[Double]]]

    var body: some View {
        GeometryReader { geometry in
            let box = Self.box(around: measured + reference)
            let photo = image.size
            let scale = min(geometry.size.width / (box.width * photo.width),
                            geometry.size.height / (box.height * photo.height))
            let shown = CGSize(width: photo.width * scale, height: photo.height * scale)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                RegionPhoto.outline(reference, in: shown)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 4]))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                RegionPhoto.outline(measured, in: shown)
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
            .frame(width: shown.width, height: shown.height)
            .offset(x: geometry.size.width / 2 - box.midX * shown.width,
                    y: geometry.size.height / 2 - box.midY * shown.height)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The regions' bounding box in 0-1 photo coordinates, with a margin so the outline has
    /// some face around it.
    static func box(around polygons: [[[Double]]]) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let points = polygons.flatMap { $0 }.filter { $0.count == 2 }
        guard let minX = points.map({ $0[0] }).min(), let maxX = points.map({ $0[0] }).max(),
              let minY = points.map({ $0[1] }).min(), let maxY = points.map({ $0[1] }).max(),
              maxX > minX, maxY > minY else { return whole }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let margin = max(rect.width, rect.height) * 0.25
        let padded = rect.insetBy(dx: -margin, dy: -margin).intersection(whole)
        return padded.isEmpty ? whole : padded
    }
}

// MARK: - Words for every Signal

/// Plain words for every Signal the device measures (`FaceMeasurer`), including those the Sleep
/// Model does not use and so has no name for. Names follow the cues in
/// `pipeline/face_pipeline/sleep_model.py`.
enum SignalGlossary {
    /// Display order for Signals outside the Sleep Model: eyes, under the eyes, skin, mouth, face.
    static let order = [
        "eye_aperture", "eye_height", "eye_opening_edges", "brow_gap",
        "under_eye_shadow", "under_eye_contrast", "under_eye_blue",
        "sclera_redness", "sclera_vs_skin_redness", "skin_chroma",
        "mouth_corner_droop", "face_width",
    ]

    private static let entries: [String: (name: String, measures: String)] = [
        "eye_aperture": ("Eyelid opening (area)", "How open your eyes are: the area between the eyelids, compared with the width of the eye."),
        "eye_height": ("Eyelid opening (height)", "How open your eyes are: the height of the eye opening, compared with its width."),
        "eye_opening_edges": ("Eyelid opening (lid edges)", "How open your eyes are: the gap between the upper and lower lid across the pupil."),
        "brow_gap": ("Upper eyelid position", "The distance from the top of each eye up to the eyebrow. A bigger gap means the upper eyelids sit lower."),
        "under_eye_shadow": ("Darkness under the eyes", "How much darker the skin just under each eye is than your cheek."),
        "under_eye_contrast": ("Darkness under the eyes (light)", "How much less light the skin under each eye gives back than your cheek."),
        "under_eye_blue": ("Blue tint under the eyes", "How much bluer the skin under each eye is than your cheek."),
        "sclera_redness": ("Redness of the eye whites", "How red the whites of your eyes are."),
        "sclera_vs_skin_redness": ("Redness of the eyes", "How red the whites of your eyes are, compared with the redness of your cheek."),
        "skin_chroma": ("Skin colour", "How much colour there is in the skin of your cheeks."),
        "mouth_corner_droop": ("Mouth corners", "How low the corners of your mouth sit compared with the middle of your lips."),
        "face_width": ("Face fullness", "How wide your face is at the jaw, compared with the distance between your eyes."),
    ]

    static func name(_ id: String) -> String { entries[id]?.name ?? id }
    static func measures(_ id: String) -> String? { entries[id]?.measures }

    /// Regions a Signal is compared against rather than read from: the cheek, for Signals that
    /// are a difference between the eye area and the skin beside it.
    static func referenceKeys(for id: String) -> [String] {
        switch id {
        case "under_eye_shadow", "under_eye_contrast", "under_eye_blue", "sclera_vs_skin_redness":
            ["cheek_left", "cheek_right"]
        default:
            []
        }
    }

    /// Raw Signal values span very different units, so three significant figures, not fixed decimals.
    static func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.significantDigits(1...3)))
    }
}
