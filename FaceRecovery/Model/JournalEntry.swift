import Foundation
import SwiftData

/// How recovered the user says they feel. A self-report, never blended into the Recovery Score
/// (CONTEXT.md, ADR 0004).
enum PerceivedRecovery: Int, CaseIterable, Identifiable {
    case exhausted = 1, tired, okay, good, great

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .exhausted: "😫"
        case .tired: "😕"
        case .okay: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }

    var title: String {
        switch self {
        case .exhausted: "Exhausted"
        case .tired: "Tired"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var detail: String {
        switch self {
        case .exhausted: "Completely worn out"
        case .tired: "Running low"
        case .okay: "Getting by"
        case .good: "Mostly rested"
        case .great: "Full of energy"
        }
    }
}

enum SleepQuality: Int, CaseIterable, Identifiable {
    case veryPoorly = 1, poorly, okay, well, veryWell

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryPoorly: "😫"
        case .poorly: "😕"
        case .okay: "😐"
        case .well: "🙂"
        case .veryWell: "😄"
        }
    }

    var title: String {
        switch self {
        case .veryPoorly: "Very poorly"
        case .poorly: "Poorly"
        case .okay: "Okay"
        case .well: "Well"
        case .veryWell: "Very well"
        }
    }
}

/// Things from the day before that plausibly show in a face the next morning. Recorded, never
/// interpreted: an Insight may not assert one of these as a cause.
enum JournalFactor: String, CaseIterable, Identifiable {
    case alcohol
    case lateCaffeine = "late_caffeine"
    case saltyFood = "salty_food"
    case lateMeal = "late_meal"
    case exercise
    case nap
    case wokeInNight = "woke_in_night"
    case pain
    case unwell
    case stress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alcohol: "Alcohol"
        case .lateCaffeine: "Coffee or tea late in the day"
        case .saltyFood: "Salty or takeaway food"
        case .lateMeal: "Late or heavy meal"
        case .exercise: "Exercise or a long walk"
        case .nap: "Daytime nap"
        case .wokeInNight: "Woke up in the night"
        case .pain: "Aches or pain"
        case .unwell: "Felt unwell"
        case .stress: "Stress or worry"
        }
    }

    var systemImage: String {
        switch self {
        case .alcohol: "wineglass"
        case .lateCaffeine: "cup.and.saucer"
        case .saltyFood: "takeoutbag.and.cup.and.straw"
        case .lateMeal: "fork.knife"
        case .exercise: "figure.walk"
        case .nap: "bed.double"
        case .wokeInNight: "moon.zzz"
        case .pain: "bandage"
        case .unwell: "thermometer.medium"
        case .stress: "cloud.rain"
        }
    }
}

/// The user's own account of one day: Perceived Recovery, sleep, medicines and anything else
/// they note. At most one per day, matched to that day's Face Scans by `dayStart`. Never sent
/// to the LLM and never part of the Recovery Score.
@Model
final class JournalEntry {
    /// Local start of the day this entry describes, the same key as `FaceScan.dayStart`.
    @Attribute(.unique) var dayStart: Date

    var createdAt: Date
    var updatedAt: Date

    /// True when the entry was answered straight after the shutter, before any Recovery Score
    /// for the day had been shown. Any later edit clears it, because by then the user has seen
    /// the number and their answer may be anchored by it (ADR 0004).
    var isBlindToScore: Bool

    /// `PerceivedRecovery` raw value, 1-5. Every answer is nil when its question was skipped.
    var perceivedRecovery: Int?
    /// `SleepQuality` raw value, 1-5.
    var sleepQuality: Int?
    /// A rough self-report in whole hours: 4 means four or fewer, 9 means nine or more.
    var hoursSlept: Int?

    /// False is a deliberate "none"; nil means the question was skipped.
    var tookMedication: Bool?
    /// Names as the user typed them. Empty unless `tookMedication` is true.
    var medications: [String]

    /// `JournalFactor` raw values, stored as strings so that retiring a factor later never
    /// breaks an old entry.
    var factors: [String]

    var notes: String

    init(dayStart: Date, isBlindToScore: Bool, now: Date = .now) {
        self.dayStart = dayStart
        self.createdAt = now
        self.updatedAt = now
        self.isBlindToScore = isBlindToScore
        self.medications = []
        self.factors = []
        self.notes = ""
    }

    static func entry(on dayStart: Date, in context: ModelContext) -> JournalEntry? {
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
