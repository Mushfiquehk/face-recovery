import Foundation

/// What the audio report says for one day, written the way a caring person would say it: warm,
/// plain, in the second person, with a gentle word at the end.
///
/// Deterministic by construction. There is no generated text and no randomness: the words come
/// from fixed templates, and the few places that vary are chosen from the day itself, so the
/// same day always reads the same way and a report can be compared across listens.
///
/// A report is only ever for a single day's Daily Sleep Prediction. It never speaks about the
/// spread or the trend across days. It describes a reading of a photograph, never health.
/// Returned one sentence at a time so each can be spoken with a pause after it.
enum DailyReport {
    static func sentences(
        dayStart: Date,
        isMeasured: Bool,
        prediction: SleepPrediction?,
        calendar: Calendar = .current
    ) -> [String] {
        var sentences = ["Here is your report for \(dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day()))."]

        guard let prediction else {
            sentences.append(contentsOf: isMeasured ? unusable : notMeasured)
            return sentences
        }

        if prediction.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            sentences.append("I am still getting to know what your face usually looks like.")
            sentences.append("After \(needed) clear morning photos, I can compare each day with your own usual.")
            sentences.append("Until then, I will show your average night, which is \(prediction.value).")
            return sentences
        }

        let band = SleepBand(value: prediction.value)
        sentences.append("Your sleep reading is \(prediction.value).")
        sentences.append(describe(band))
        sentences.append(comparison(of: prediction))
        sentences.append(contentsOf: reasons(in: prediction))
        sentences.append(contentsOf: kindWord(for: band, dayStart: dayStart, calendar: calendar))
        return sentences
    }

    // MARK: Phrases

    private static let unusable = [
        "I could not get a clear reading from this photo, so there is no reading for this day.",
        "Take your glasses off, face a window, and hold the phone steady. That makes a big difference.",
        "Do not worry. A better photo next time will put things right.",
    ]

    private static let notMeasured = [
        "This day has not been read yet.",
        "Open it and choose Read this scan whenever you are ready.",
    ]

    private static func describe(_ band: SleepBand) -> String {
        switch band {
        case .optimal: "That is a good one. Your face looks well rested today."
        case .sufficient: "Your face looks a little short on sleep today."
        case .poor: "Your face looks short on sleep today."
        }
    }

    private static func comparison(of prediction: SleepPrediction) -> String {
        let average = Int(prediction.startingValue.rounded())
        let difference = prediction.value - average
        switch difference {
        case 0: return "That is right at your average night."
        case 1...: return "That is \(difference) above your average night."
        default: return "That is \(-difference) below your average night."
        }
    }

    /// The one or two Contributions that moved the reading most, in everyday words.
    private static func reasons(in prediction: SleepPrediction) -> [String] {
        let notable = prediction.contributions.filter { !$0.isSteady && abs($0.points) >= 1 }.prefix(2)
        guard let first = notable.first else {
            return ["Nothing in your face stands out from your usual."]
        }
        var out = ["The biggest change is that your photo shows \(first.words) than usual."]
        if notable.count > 1 {
            out.append("It also shows \(notable[notable.index(after: notable.startIndex)].words) than usual.")
        }
        return out
    }

    /// A closing line for the band. Which of the three is chosen depends only on the date, so
    /// the same day always gets the same one.
    private static func kindWord(for band: SleepBand, dayStart: Date, calendar: Calendar) -> [String] {
        let lines: [[String]]
        switch band {
        case .optimal:
            lines = [
                ["Lovely to see. Keep doing whatever you are doing."],
                ["Well done. Enjoy the day."],
                ["That is good news. Look after yourself, and enjoy it."],
            ]
        case .sufficient:
            lines = [
                ["Nothing to worry about. Maybe have some water and a proper meal."],
                ["A gentle day might suit you. Try to rest when you can."],
                ["It happens to all of us. Be kind to yourself today."],
            ]
        case .poor:
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
