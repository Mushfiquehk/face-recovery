import Foundation

/// The questions of a Journal Entry, in the order the guided flow asks them.
enum JournalQuestion: Int, CaseIterable, Identifiable {
    case feeling, sleep, medicines, factors, notes

    var id: Int { rawValue }

    /// The short label used in the journal summary.
    var label: String {
        switch self {
        case .feeling: "How you felt"
        case .sleep: "Sleep"
        case .medicines: "Medicines"
        case .factors: "Other factors"
        case .notes: "Notes"
        }
    }

    /// Worded for the day being journaled: "today" only makes sense on the day itself.
    func prompt(isToday: Bool) -> String {
        switch self {
        case .feeling: isToday ? "How do you feel today?" : "How did you feel that day?"
        case .sleep: isToday ? "How did you sleep last night?" : "How did you sleep the night before?"
        case .medicines: isToday ? "Have you taken any medicine in the last day?" : "Did you take any medicine that day?"
        case .factors: isToday ? "Since yesterday, did any of these happen?" : "The day before, did any of these happen?"
        case .notes: "Anything else you'd like to note?"
        }
    }

    var hint: String {
        switch self {
        case .feeling: "Think about your energy and how rested you feel overall."
        case .sleep: "Choose one, and the hours if you know them roughly."
        case .medicines: "Include sleep aids, pain relief and supplements."
        case .factors: "Tap all that apply."
        case .notes: "Optional. Tap the microphone on the keyboard to speak instead of typing."
        }
    }
}

/// A Journal Entry's answers as they are being edited. Kept apart from the stored entry so that
/// leaving the journal without saving really does discard what was changed.
struct JournalAnswers: Equatable {
    var perceivedRecovery: PerceivedRecovery?
    var sleepQuality: SleepQuality?
    var hoursSlept: Int?
    var tookMedication: Bool?
    var medications: [String] = []
    var factors: Set<JournalFactor> = []
    var notes = ""

    /// The choices offered for `hoursSlept`. The ends are open: 4 means "4 or less".
    static let hourChoices = Array(4...9)

    init(_ entry: JournalEntry? = nil) {
        guard let entry else { return }
        perceivedRecovery = entry.perceivedRecovery.flatMap(PerceivedRecovery.init(rawValue:))
        sleepQuality = entry.sleepQuality.flatMap(SleepQuality.init(rawValue:))
        hoursSlept = entry.hoursSlept
        tookMedication = entry.tookMedication
        medications = entry.medications
        factors = Set(entry.factors.compactMap(JournalFactor.init(rawValue:)))
        notes = entry.notes
    }

    func isAnswered(_ question: JournalQuestion) -> Bool {
        switch question {
        case .feeling: perceivedRecovery != nil
        case .sleep: sleepQuality != nil || hoursSlept != nil
        case .medicines: tookMedication != nil
        case .factors: !factors.isEmpty
        case .notes: !trimmedNotes.isEmpty
        }
    }

    func apply(to entry: JournalEntry) {
        entry.perceivedRecovery = perceivedRecovery?.rawValue
        entry.sleepQuality = sleepQuality?.rawValue
        entry.hoursSlept = hoursSlept
        entry.tookMedication = tookMedication
        // Medicines picked before switching the answer to "No" are not medicines taken.
        entry.medications = tookMedication == true ? medications : []
        // Stored in the order the flow shows them, not the order they were tapped.
        entry.factors = JournalFactor.allCases.filter(factors.contains).map(\.rawValue)
        entry.notes = trimmedNotes
    }

    /// What the journal summary shows for a question, or nil when it was not answered.
    func summary(of question: JournalQuestion) -> String? {
        switch question {
        case .feeling:
            return perceivedRecovery.map { "\($0.emoji) \($0.title)" }
        case .sleep:
            switch (sleepQuality, hoursSlept) {
            case let (quality?, hours?): return "\(quality.emoji) \(quality.title), \(Self.hoursLabel(hours).lowercased())"
            case let (quality?, nil): return "\(quality.emoji) \(quality.title)"
            case let (nil, hours?): return Self.hoursLabel(hours)
            case (nil, nil): return nil
            }
        case .medicines:
            switch tookMedication {
            case false?: return "None"
            case true?: return medications.isEmpty ? "Yes" : medications.joined(separator: ", ")
            case nil: return nil
            }
        case .factors:
            let titles = JournalFactor.allCases.filter(factors.contains).map(\.title)
            return titles.isEmpty ? nil : titles.joined(separator: ", ")
        case .notes:
            return trimmedNotes.isEmpty ? nil : trimmedNotes
        }
    }

    static func hoursLabel(_ hours: Int) -> String {
        if hours == hourChoices.first { return "\(hours) hours or less" }
        if hours == hourChoices.last { return "\(hours) hours or more" }
        return "About \(hours) hours"
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
