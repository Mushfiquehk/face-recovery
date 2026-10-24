import Foundation
import SwiftData

/// A short message about one day, which the user's own Shortcuts automation sends to family or a
/// friend (ADR 0006). Written in the first person, because it goes out from the user's phone in
/// their name, and in the same plain words the app uses.
///
/// Deterministic, like the Daily Report: fixed wording filled in from the day, so the people who
/// receive it learn to read it at a glance. It only ever contains what the user switched on.
/// Photos and notes are never part of it, whatever the settings: a photo is the most identifying
/// thing the app holds, and notes are written for the user alone.
enum FamilyUpdate {
    /// What the user chose to include. Each is stored in UserDefaults under its own key, so
    /// Settings (through `@AppStorage`) and the App Intent read the same choices.
    enum Setting: String, CaseIterable {
        case enabled = "familyUpdateEnabled"
        case sleepReading = "familyUpdateSleepReading"
        case feeling = "familyUpdateFeeling"
        case sleep = "familyUpdateSleep"
        case factors = "familyUpdateFactors"
        case medicines = "familyUpdateMedicines"

        /// Off until the user turns it on, and the more personal answers stay out until chosen.
        var defaultValue: Bool {
            switch self {
            case .enabled, .factors, .medicines: false
            case .sleepReading, .feeling, .sleep: true
            }
        }

        var isOn: Bool {
            UserDefaults.standard.object(forKey: rawValue) as? Bool ?? defaultValue
        }
    }

    struct Options: Equatable {
        var sleepReading = Setting.sleepReading.defaultValue
        var feeling = Setting.feeling.defaultValue
        var sleep = Setting.sleep.defaultValue
        var factors = Setting.factors.defaultValue
        var medicines = Setting.medicines.defaultValue

        static var current: Options {
            Options(
                sleepReading: Setting.sleepReading.isOn,
                feeling: Setting.feeling.isOn,
                sleep: Setting.sleep.isOn,
                factors: Setting.factors.isOn,
                medicines: Setting.medicines.isOn
            )
        }

        var includesJournal: Bool { feeling || sleep || factors || medicines }
    }

    /// Today's update, read from the store.
    @MainActor
    static func today(
        in context: ModelContext,
        options: Options = .current,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> String {
        let dayStart = calendar.startOfDay(for: now)
        let scans = try context.fetch(FetchDescriptor<FaceScan>())
        return text(
            dayStart: dayStart,
            day: DayHistory.day(dayStart, from: scans),
            journal: JournalEntry.entry(on: dayStart, in: context),
            options: options
        )
    }

    /// Worded for the day it describes being today, since that is the only day an automation
    /// sends.
    static func text(dayStart: Date, day: DayEntry?, journal: JournalEntry?, options: Options) -> String {
        var lines = ["Face Recovery, \(dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide)))"]
        var showsReading = false

        if options.sleepReading {
            if let prediction = day?.dailyPrediction {
                if prediction.isBaselineForming {
                    lines.append("The app is still learning what my face usually looks like, so there is no sleep reading yet.")
                } else {
                    lines.append("Sleep reading: \(prediction.value) out of 100. \(SleepBand(value: prediction.value).label).")
                    showsReading = true
                }
            } else if let day {
                lines.append(day.canonical.isMeasured
                             ? "My photo today was not clear enough for a sleep reading."
                             : "My photo today has not been read yet.")
            } else {
                lines.append("I have not taken my morning photo yet.")
            }
        }

        if options.includesJournal {
            let answers = JournalAnswers(journal)
            var answered: [String] = []
            if options.feeling, let feeling = answers.summary(of: .feeling) {
                answered.append("How I feel: \(feeling)")
            }
            if options.sleep, let sleep = answers.summary(of: .sleep) {
                answered.append("How I slept: \(sleep)")
            }
            if options.factors, let factors = answers.summary(of: .factors) {
                answered.append("Since yesterday: \(factors)")
            }
            if options.medicines, let medicines = answers.summary(of: .medicines) {
                answered.append("Medicines: \(medicines)")
            }
            lines.append(contentsOf: answered.isEmpty ? ["I have not answered today's questions yet."] : answered)
        }

        if showsReading {
            lines.append("(This is a reading from a photo, not a medical test.)")
        }
        return lines.joined(separator: "\n")
    }
}
