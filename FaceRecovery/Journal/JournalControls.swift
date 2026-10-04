import SwiftUI

/// One answer in the journal: a large card, at least 64pt tall, with the whole card as the tap
/// target. Selection is shown by a filled check as well as by colour, so it still reads for
/// anyone who cannot tell the tint apart.
struct JournalOption: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let emoji {
                    Text(emoji)
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                } else if let systemImage, !dynamicTypeSize.isAccessibilitySize {
                    // Decorative, so it gives its width back to the words at the largest sizes.
                    Image(systemName: systemImage)
                        .font(.title2)
                        .frame(minWidth: 32)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .journalCard(isSelected: isSelected)
        }
        .buttonStyle(JournalPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A short answer laid out in a grid, such as an hour count or Yes / No.
struct JournalChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: 1.5)
                )
        }
        .buttonStyle(JournalPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Dims on press, so a tap is visibly acknowledged even though the cards are custom drawn.
struct JournalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    /// The card every journal answer sits on: an outline at rest, a heavier tinted one when chosen.
    func journalCard(isSelected: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2.5 : 1.5)
        )
    }
}
