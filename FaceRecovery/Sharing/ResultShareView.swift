import SwiftUI

/// Shows the Result Card exactly as it will be sent, lets the user choose whether their photo is
/// on it, and hands it to the iPhone's own share options: Messages, Mail, WhatsApp, Instagram,
/// Save Image and the rest. Nothing leaves the phone until the user picks one (ADR 0008).
struct ResultShareView: View {
    let dayStart: Date
    let scan: FaceScan
    let prediction: SleepPrediction

    @Environment(\.dismiss) private var dismiss
    /// Remembered between shares, and off until the user turns it on: a face is the most
    /// identifying thing the app holds.
    @AppStorage("resultCardIncludesPhoto") private var includesPhoto = false
    @State private var card: UIImage?

    private var message: String { ResultCard.message(dayStart: dayStart, prediction: prediction) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview

                    Toggle(isOn: $includesPhoto) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Include my photo")
                                .font(.body.weight(.semibold))
                            Text("Your journal answers and notes are never included.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(minHeight: 60)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    if let card {
                        ShareLink(
                            item: Image(uiImage: card),
                            subject: Text("My sleep reading"),
                            message: Text(message),
                            preview: SharePreview("My sleep reading", image: Image(uiImage: card))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share this day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: includesPhoto) {
                card = ResultCard.render(
                    dayStart: dayStart,
                    prediction: prediction,
                    photo: includesPhoto ? PhotoStore.thumbnail(scan.photoFilename, maxPixelSize: 300) : nil
                )
            }
        }
    }

    private var preview: some View {
        Group {
            if let card {
                Image(uiImage: card)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(.secondarySystemGroupedBackground)
                    .overlay { ProgressView() }
            }
        }
        .aspectRatio(ResultCard.size.width / ResultCard.size.height, contentMode: .fit)
        .frame(maxWidth: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

/// Opens the share preview for one day. Only offered for a real Daily Sleep Prediction: while
/// Baseline Forming the number is the average night, not a reading, and read cold by someone
/// else it would mislead (the same rule as Family Updates, ADR 0006).
struct ShareResultButton: View {
    let dayStart: Date
    let scan: FaceScan
    let prediction: SleepPrediction

    @State private var isSharing = false

    var body: some View {
        Button {
            isSharing = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Shows a picture of this day's reading to send or post")
        .sheet(isPresented: $isSharing) {
            ResultShareView(dayStart: dayStart, scan: scan, prediction: prediction)
        }
    }
}
