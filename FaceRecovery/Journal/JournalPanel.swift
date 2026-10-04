import SwiftUI
import SwiftData

/// A day's Journal Entry, or a button to write one. Each answer opens just that question, so
/// changing one thing never means stepping through the whole journal again.
struct JournalPanel: View {
    let dayStart: Date

    /// Owned here rather than passed in, so the screen updates the moment the entry is saved.
    @Query private var entries: [JournalEntry]
    @State private var presented: JournalFlowView.Mode?

    init(dayStart: Date) {
        self.dayStart = dayStart
        _entries = Query(filter: #Predicate<JournalEntry> { $0.dayStart == dayStart })
    }

    var body: some View {
        Group {
            if let entry = entries.first {
                summary(JournalAnswers(entry))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Note how you felt, how you slept and any medicines you took.")
                        .foregroundStyle(.secondary)
                    Button {
                        presented = .guided
                    } label: {
                        Label("Add journal entry", systemImage: "square.and.pencil")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .fullScreenCover(item: $presented) { mode in
            JournalFlowView(dayStart: dayStart, existing: entries.first, mode: mode)
        }
    }

    private func summary(_ answers: JournalAnswers) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(JournalQuestion.allCases) { question in
                if question != JournalQuestion.allCases.first {
                    Divider()
                }
                row(question, value: answers.summary(of: question))
            }

            Text("Tap an answer to change it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func row(_ question: JournalQuestion, value: String?) -> some View {
        Button {
            presented = .single(question)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(question.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value ?? placeholder(for: question))
                        .foregroundStyle(value == nil ? .secondary : .primary)
                        .lineLimit(question == .notes ? 4 : nil)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        // Plain, so each row is its own target even inside a List row.
        .buttonStyle(.plain)
        .accessibilityHint("Opens this question to change your answer")
    }

    /// An empty multi-select or note is a real answer ("nothing to add"), not a skipped one.
    private func placeholder(for question: JournalQuestion) -> String {
        switch question {
        case .factors, .notes: "None"
        case .feeling, .sleep, .medicines: "Not answered"
        }
    }
}
