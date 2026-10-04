import SwiftUI
import SwiftData

/// Writes or edits a day's Journal Entry, one question per screen.
///
/// Built for older users: large text and targets, plain wording, the same Back / Next bar at the
/// bottom of every screen, every question skippable, and presented full screen so that no
/// stray swipe can throw the answers away.
struct JournalFlowView: View {
    enum Mode: Hashable, Identifiable {
        /// Every question in turn, for a new entry.
        case guided
        /// One question, opened by tapping it in the journal summary.
        case single(JournalQuestion)

        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Grows with the text size, so the hour choices drop from three columns to two to one
    /// instead of wrapping "4 or less" across lines.
    @ScaledMetric(relativeTo: .title3) private var hourChipWidth: CGFloat = 100

    /// Every entry, newest first, so a medicine typed once becomes a single tap afterwards.
    @Query(sort: \JournalEntry.dayStart, order: .reverse) private var allEntries: [JournalEntry]

    private let dayStart: Date
    private let existing: JournalEntry?
    private let mode: Mode
    private let isBlindToScore: Bool
    private let original: JournalAnswers

    @State private var answers: JournalAnswers
    @State private var question: JournalQuestion
    @State private var medicineChoices: [String] = []
    @State private var newMedicine = ""
    @State private var isConfirmingExit = false
    @State private var saveError: String?
    @FocusState private var isTyping: Bool
    @AccessibilityFocusState private var isQuestionFocused: Bool

    /// - Parameter isBlindToScore: true only when presented straight after the shutter, before
    ///   any Recovery Score for the day has been shown (ADR 0004).
    init(dayStart: Date, existing: JournalEntry?, mode: Mode = .guided, isBlindToScore: Bool = false) {
        self.dayStart = dayStart
        self.existing = existing
        self.mode = mode
        self.isBlindToScore = isBlindToScore

        let answers = JournalAnswers(existing)
        original = answers
        _answers = State(initialValue: answers)
        switch mode {
        case .guided: _question = State(initialValue: .feeling)
        case .single(let question): _question = State(initialValue: question)
        }
    }

    private var sequence: [JournalQuestion] {
        switch mode {
        case .guided: JournalQuestion.allCases
        case .single(let question): [question]
        }
    }

    private var position: Int { sequence.firstIndex(of: question) ?? 0 }
    private var isLast: Bool { position == sequence.count - 1 }
    private var isToday: Bool { Calendar.current.isDateInToday(dayStart) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.prompt(isToday: isToday))
                                .font(.title.weight(.bold))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($isQuestionFocused)
                            Text(question.hint)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        answerControls
                    }
                    .padding()
                }
                // A fresh scroll view per question, so each one starts at the top.
                .id(question)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isTyping) { _, isTyping in
                    guard isTyping, question == .medicines else { return }
                    // After the keyboard has settled, or the field is measured against the old
                    // safe area and ends up hidden behind the Back / Next bar.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation { proxy.scrollTo(Self.medicineFieldID, anchor: .bottom) }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(existing == nil ? "Journal" : "Edit journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isBlindToScore ? "Not now" : "Cancel", action: leave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTyping = false }
                }
            }
            .alert("Leave the journal?", isPresented: $isConfirmingExit) {
                Button("Save answers", action: save)
                Button("Discard answers", role: .destructive) { dismiss() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Your answers haven't been saved yet.")
            }
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: loadMedicineChoices)
        .onChange(of: question) { isQuestionFocused = true }
    }

    // MARK: Header and navigation

    @ViewBuilder
    private var header: some View {
        if isBlindToScore && position == 0 {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Photo saved. Your score comes next.")
            }
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }

        if !isToday {
            Text(dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)
                .foregroundStyle(.secondary)
        }

        if sequence.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Question \(position + 1) of \(sequence.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(sequence.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= position ? Color.accentColor : Color(.systemGray4))
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    /// Side by side when both labels fit on one line; stacked, forward first, when large text
    /// would otherwise wrap them a letter at a time.
    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backButton(singleLine: true)
                forwardButton(singleLine: true)
            }
            VStack(spacing: 10) {
                forwardButton(singleLine: false)
                backButton(singleLine: false)
            }
        }
        .font(.title3.weight(.semibold))
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// `singleLine` reports a label's true width so `ViewThatFits` can tell whether the pair
    /// fits side by side; stacked, the labels may wrap rather than run off the screen.
    @ViewBuilder
    private func backButton(singleLine: Bool) -> some View {
        if position > 0 {
            Button(action: goBack) {
                Label("Back", systemImage: "chevron.left")
                    .lineLimit(singleLine ? 1 : nil)
                    .fixedSize(horizontal: singleLine, vertical: false)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func forwardButton(singleLine: Bool) -> some View {
        Button(action: goForward) {
            Text(forwardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(singleLine ? 1 : nil)
                .fixedSize(horizontal: singleLine, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    /// Says what the button will actually do: "Skip" when nothing is chosen, so moving on
    /// without an answer is a deliberate, visible choice.
    private var forwardTitle: String {
        if isLast { return isBlindToScore ? "Save and see score" : "Save" }
        if answers.isAnswered(question) { return "Next" }
        return question == .factors ? "None of these" : "Skip"
    }

    private func goForward() {
        isTyping = false
        if isLast {
            save()
        } else {
            move(to: sequence[position + 1])
        }
    }

    private func goBack() {
        isTyping = false
        move(to: sequence[position - 1])
    }

    private func move(to next: JournalQuestion) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            question = next
        }
    }

    // MARK: Questions

    @ViewBuilder
    private var answerControls: some View {
        switch question {
        case .feeling: feelingQuestion
        case .sleep: sleepQuestion
        case .medicines: medicinesQuestion
        case .factors: factorsQuestion
        case .notes: notesQuestion
        }
    }

    private var feelingQuestion: some View {
        VStack(spacing: 12) {
            ForEach(PerceivedRecovery.allCases.reversed()) { level in
                JournalOption(
                    emoji: level.emoji,
                    title: level.title,
                    detail: level.detail,
                    isSelected: answers.perceivedRecovery == level
                ) {
                    choose(level, for: \.perceivedRecovery)
                }
            }
        }
    }

    private var sleepQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SleepQuality.allCases.reversed()) { quality in
                JournalOption(
                    emoji: quality.emoji,
                    title: quality.title,
                    isSelected: answers.sleepQuality == quality
                ) {
                    choose(quality, for: \.sleepQuality)
                }
            }

            Text("Roughly how many hours?")
                .font(.title3.weight(.semibold))
                .padding(.top, 12)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: hourChipWidth), spacing: 10)], spacing: 10) {
                ForEach(JournalAnswers.hourChoices, id: \.self) { hours in
                    JournalChip(title: hourChipTitle(hours), isSelected: answers.hoursSlept == hours) {
                        choose(hours, for: \.hoursSlept)
                    }
                    .accessibilityLabel(JournalAnswers.hoursLabel(hours))
                }
            }
        }
    }

    private var medicinesQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                JournalChip(title: "Yes", isSelected: answers.tookMedication == true) {
                    choose(true, for: \.tookMedication)
                }
                JournalChip(title: "No", isSelected: answers.tookMedication == false) {
                    choose(false, for: \.tookMedication)
                }
            }

            if answers.tookMedication != false,
               !lastMedicines.isEmpty,
               !Set(lastMedicines).isSubset(of: answers.medications) {
                sameAsLastTimeButton
            }

            if answers.tookMedication == true {
                Text("Which ones?")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 8)

                ForEach(medicineChoices, id: \.self) { name in
                    JournalOption(
                        systemImage: "pills",
                        title: name,
                        isSelected: answers.medications.contains(name)
                    ) {
                        toggleMedicine(name)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Type a medicine name", text: $newMedicine)
                        .font(.title3)
                        .textInputAutocapitalization(.words)
                        // Autocorrect turns drug names into ordinary words.
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isTyping)
                        .onSubmit(addMedicine)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .journalCard()
                        .id(Self.medicineFieldID)

                    Button(action: addMedicine) {
                        Text("Add")
                            .frame(minHeight: 44)
                    }
                    .font(.title3.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newMedicine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var sameAsLastTimeButton: some View {
        Button(action: useLastMedicines) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Same as last time")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(lastMedicines.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .journalCard()
        }
        .buttonStyle(JournalPressStyle())
    }

    private var factorsQuestion: some View {
        VStack(spacing: 10) {
            ForEach(JournalFactor.allCases) { factor in
                JournalOption(
                    systemImage: factor.systemImage,
                    title: factor.title,
                    isSelected: answers.factors.contains(factor)
                ) {
                    if answers.factors.contains(factor) {
                        answers.factors.remove(factor)
                    } else {
                        answers.factors.insert(factor)
                    }
                }
            }
        }
    }

    private var notesQuestion: some View {
        TextEditor(text: $answers.notes)
            .font(.title3)
            .focused($isTyping)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: 200)
            .journalCard()
            .overlay(alignment: .topLeading) {
                if answers.notes.isEmpty {
                    Text("For example: a late night, a new medicine, or feeling under the weather.")
                        .font(.title3)
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    // MARK: Answers

    /// Single-choice answers toggle: tapping the chosen one again clears it, so a mis-tap
    /// can always be taken back.
    private func choose<Value: Equatable>(_ value: Value, for keyPath: WritableKeyPath<JournalAnswers, Value?>) {
        answers[keyPath: keyPath] = answers[keyPath: keyPath] == value ? nil : value
    }

    private func hourChipTitle(_ hours: Int) -> String {
        if hours == JournalAnswers.hourChoices.first { return "\(hours) or less" }
        if hours == JournalAnswers.hourChoices.last { return "\(hours) or more" }
        return "\(hours)"
    }

    /// The medicines of the most recent earlier day that had any, for "Same as last time".
    private var lastMedicines: [String] {
        allEntries.first { $0.dayStart < dayStart && !$0.medications.isEmpty }?.medications ?? []
    }

    /// Medicines from this entry and the last 30, most recent first. Built once, so a row never
    /// moves or vanishes while it is being tapped.
    private func loadMedicineChoices() {
        guard medicineChoices.isEmpty else { return }
        for name in answers.medications + allEntries.prefix(30).flatMap(\.medications) {
            _ = choice(for: name)
        }
    }

    /// Matches a name to an existing choice ignoring case, so "metformin" and "Metformin" are
    /// one medicine. Adds it as a new choice when there is no match.
    private func choice(for name: String) -> String {
        if let match = medicineChoices.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        medicineChoices.append(name)
        return name
    }

    private func toggleMedicine(_ name: String) {
        if let index = answers.medications.firstIndex(of: name) {
            answers.medications.remove(at: index)
        } else {
            answers.medications.append(name)
        }
    }

    private func addMedicine() {
        let name = newMedicine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let chosen = choice(for: name)
        if !answers.medications.contains(chosen) {
            answers.medications.append(chosen)
        }
        newMedicine = ""
    }

    private static let medicineFieldID = "medicineField"

    /// Adds last time's medicines to whatever is already ticked, never taking any away.
    private func useLastMedicines() {
        answers.tookMedication = true
        for name in lastMedicines.map(choice(for:)) where !answers.medications.contains(name) {
            answers.medications.append(name)
        }
    }

    // MARK: Saving

    private func leave() {
        if answers == original {
            dismiss()
        } else {
            isConfirmingExit = true
        }
    }

    private func save() {
        // Nothing new to keep. Skipping every question of a new entry is the same as "Not now".
        guard answers != original else { return dismiss() }

        let entry: JournalEntry
        if let found = existing ?? JournalEntry.entry(on: dayStart, in: modelContext) {
            entry = found
            // Anyone editing has seen the day's score by now, so the answers may be anchored by it.
            entry.isBlindToScore = false
        } else {
            entry = JournalEntry(dayStart: dayStart, isBlindToScore: isBlindToScore)
            modelContext.insert(entry)
        }
        answers.apply(to: entry)
        entry.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
