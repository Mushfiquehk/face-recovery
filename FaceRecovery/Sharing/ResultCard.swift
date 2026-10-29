import SwiftUI

/// One day's Daily Sleep Prediction drawn as a picture to post or send, the way a fitness app
/// shares a workout (ADR 0008). It shows the number, its band, how it compares with the average
/// night and the few Contributions that moved it most. The photo is on it only when the user
/// switches it on; notes, medicines and the rest of the Journal Entry never are.
///
/// Always drawn in light mode at one fixed size and text size, so the picture looks the same
/// whoever receives it and whatever the sender's settings are.
struct ResultCard: View {
    let dayStart: Date
    let prediction: SleepPrediction
    /// A small copy of the scan's photo, or nil to leave the face off the card.
    let photo: UIImage?

    static let size = CGSize(width: 360, height: 450)

    private var band: SleepBand { SleepBand(value: prediction.value) }

    /// At most three, and only those that moved the number by a whole point.
    private var reasons: [Contribution] {
        Array(prediction.contributions.filter { !$0.isSteady && $0.roundedPoints != 0 }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 12)
            reading
            Spacer(minLength: 12)
            if !reasons.isEmpty {
                reasonList
                Spacer(minLength: 12)
            }
            Text("A reading from a face photo, not a medical test.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [band.color.opacity(0.16), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .center
            )
            .background(Color(.systemBackground))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(dayStart.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(dayStart.formatted(.dateTime.day().month(.wide).year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("Face Recovery")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var reading: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(band.color.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: Double(prediction.value) / 100)
                    .stroke(band.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(prediction.value)")
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    Text("out of 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .frame(width: 136, height: 136)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sleep reading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(band.label)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(band.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.comparison(prediction))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reasonList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What stood out")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(reasons) { contribution in
                HStack {
                    Text(contribution.signal.name)
                    Spacer(minLength: 8)
                    Text(contribution.pointsText)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(contribution.colour)
                }
                .font(.body)
            }
        }
    }

    static func comparison(_ prediction: SleepPrediction) -> String {
        let average = Int(prediction.startingValue.rounded())
        let difference = prediction.value - average
        return switch difference {
        case 0: "Right at my average night of \(average)"
        case 1...: "\(difference) above my average night of \(average)"
        default: "\(-difference) below my average night of \(average)"
        }
    }

    /// The words sent alongside the picture, for apps that take text too, such as Messages and
    /// Mail. First person, because it goes out in the user's name, like a Family Update.
    static func message(dayStart: Date, prediction: SleepPrediction) -> String {
        let band = SleepBand(value: prediction.value)
        return "My sleep reading for \(dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(prediction.value) out of 100. \(band.label). (A reading from a face photo, not a medical test.)"
    }

    /// The card as a 1080 × 1350 picture, the portrait size social apps show without cropping.
    @MainActor
    static func render(dayStart: Date, prediction: SleepPrediction, photo: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(
            content: ResultCard(dayStart: dayStart, prediction: prediction, photo: photo)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}
