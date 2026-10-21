import SwiftUI

/// Four dots and a number pad. Keys are 76pt tall with large digits, and the whole pad scrolls
/// so it still fits at the biggest accessibility text sizes. The parent owns what happens with
/// the finished PIN and what to say about it; the pad just clears itself afterwards.
struct PinPad: View {
    let title: String
    var message: String? = nil
    var messageIsError = false
    var isDisabled = false
    let onComplete: (String) -> Void

    @State private var entry = ""

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                HStack(spacing: 20) {
                    ForEach(0..<PinStore.length, id: \.self) { index in
                        Circle()
                            .fill(index < entry.count ? Color.accentColor : Color.clear)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: 22, height: 22)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.count) of \(PinStore.length) digits entered")

                // Always present so the keys do not jump when a message appears.
                Text(message ?? " ")
                    .font(.title3)
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 56, alignment: .top)

                VStack(spacing: 12) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { digit in
                                key(digit)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 76)
                        key("0")
                        Button {
                            if !entry.isEmpty { entry.removeLast() }
                        } label: {
                            Image(systemName: "delete.left")
                                .font(.title)
                                .frame(maxWidth: .infinity, minHeight: 76)
                        }
                        .disabled(isDisabled || entry.isEmpty)
                        .accessibilityLabel("Delete")
                    }
                }
                .frame(maxWidth: 360)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.selection, trigger: entry)
    }

    private func key(_ digit: String) -> some View {
        Button {
            guard entry.count < PinStore.length else { return }
            entry.append(digit)
            guard entry.count == PinStore.length else { return }
            let pin = entry
            Task {
                // Let the fourth dot show before the pad clears.
                try? await Task.sleep(for: .milliseconds(150))
                onComplete(pin)
                entry = ""
            }
        } label: {
            Text(digit)
                .font(.largeTitle.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
