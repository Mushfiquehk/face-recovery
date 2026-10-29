import SwiftUI

/// One large button that reads a single day's report aloud, and stops it on a second tap.
/// Plain words and a full-width target, for older users.
struct AudioReportButton: View {
    let sentences: [String]

    @State private var player = AudioReportPlayer()

    var body: some View {
        Button {
            player.toggle(sentences)
        } label: {
            Label(
                player.isSpeaking ? "Stop" : "Listen",
                systemImage: player.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel(player.isSpeaking ? "Stop the report" : "Listen to this day's report")
        .accessibilityHint("Reads this day's score aloud")
        .onDisappear { player.stop() }
    }
}
