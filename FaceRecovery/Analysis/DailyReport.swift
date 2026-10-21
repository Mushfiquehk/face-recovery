import Foundation

extension RecoveryScore {
    /// The Signal furthest from baseline, if any moved enough to be worth calling out.
    var biggestMover: Signal? {
        Signal.allCases
            .max { abs(self[deviation: $0]) < abs(self[deviation: $1]) }
            .flatMap { abs(self[deviation: $0]) >= 5 ? $0 : nil }
    }
}

/// What the audio report says for one day, written the way a caring person would say it: warm,
/// plain, in the second person, with a gentle word at the end.
///
/// Deterministic by construction. There is no generated text and no randomness: the words come
/// from fixed templates, and the few places that vary are chosen from the day itself, so the
/// same day always reads the same way and a report can be compared across listens.
///
/// A report is only ever for a single day's Daily Recovery Score. It never speaks about the
/// spread or the trend across days. It describes a reading of a photograph, never health.
/// Returned one sentence at a time so each can be spoken with a pause after it.
enum DailyReport {
    static func sentences(
        dayStart: Date,
        isScored: Bool,
        score: RecoveryScore?,
        calendar: Calendar = .current
    ) -> [String] {
        var sentences = ["Here is your report for \(dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day()))."]

        guard let score else {
            sentences.append(contentsOf: isScored ? unusable : notScored)
            return sentences
        }

        let band = RecoveryBand(value: score.value)
        sentences.append("Your score is \(score.value).")
        sentences.append(describe(band))

        if score.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            sentences.append("I am still getting to know what is normal for you.")
            sentences.append("After \(needed) clear scans, I can compare each day with your own usual.")
            sentences.append("Until then, this score comes from today's photo alone.")
        } else {
            sentences.append(comparison(of: score.value))
            sentences.append(contentsOf: mover(in: score))
        }

        sentences.append(contentsOf: kindWord(for: band, dayStart: dayStart, calendar: calendar))
        return sentences
    }

    // MARK: Phrases

    private static let unusable = [
        "I could not get a clear reading from this photo, so there is no score for this day.",
        "Good light on your face and a steady phone make a big difference.",
        "Do not worry. A better photo next time will put things right.",
    ]

    private static let notScored = [
        "This day has not been scored yet.",
        "Open it and choose Score this scan whenever you are ready.",
    ]

    private static func describe(_ band: RecoveryBand) -> String {
        switch band {
        case .high: "That is a good one. You are looking rested today."
        case .medium: "You are looking a little tired today."
        case .low: "You are looking quite tired today."
        }
    }

    private static var normal: Int { Int(ScoreTuning.default.atBaselineScore) }

    private static func comparison(of value: Int) -> String {
        switch value - normal {
        case 0: "That is right where you usually are."
        case 1...: "That is \(value - normal) better than you usually are."
        default: "That is \(normal - value) lower than you usually are."
        }
    }

    /// The one Signal that moved most, in everyday words. Higher deviation means more
    /// pronounced, which reads as worse.
    private static func mover(in score: RecoveryScore) -> [String] {
        guard let signal = score.biggestMover else {
            return ["Nothing stands out from your usual."]
        }
        let name = signal.displayName.lowercased()
        return score[deviation: signal] > 0
            ? ["The biggest change is your \(name), which looks a bit stronger than usual."]
            : ["The biggest change is your \(name), which looks calmer than usual."]
    }

    /// A closing line for the band. Which of the three is chosen depends only on the date, so
    /// the same day always gets the same one.
    private static func kindWord(for band: RecoveryBand, dayStart: Date, calendar: Calendar) -> [String] {
        let lines: [[String]]
        switch band {
        case .high:
            lines = [
                ["Lovely to see. Keep doing whatever you are doing."],
                ["Well done. Enjoy the day."],
                ["That is good news. Look after yourself, and enjoy it."],
            ]
        case .medium:
            lines = [
                ["Nothing to worry about. Maybe have some water and a proper meal."],
                ["A gentle day might suit you. Try to rest when you can."],
                ["It happens to all of us. Be kind to yourself today."],
            ]
        case .low:
            lines = [
                ["Be gentle with yourself today, and rest if you can.", "This is only a reading from your photo, so listen to how you feel too."],
                ["Take it easy today. Water, food, and a little rest will help.", "This is only a reading from your photo, so listen to how you feel too."],
                ["It is all right to slow down today.", "This is only a reading from your photo, so listen to how you feel too."],
            ]
        }
        let day = calendar.ordinality(of: .day, in: .era, for: dayStart) ?? 0
        return lines[day % lines.count]
    }
}
