import Foundation

extension RecoveryScore {
    /// The Signal furthest from baseline, if any moved enough to be worth calling out.
    var biggestMover: Signal? {
        Signal.allCases
            .max { abs(self[deviation: $0]) < abs(self[deviation: $1]) }
            .flatMap { abs(self[deviation: $0]) >= 5 ? $0 : nil }
    }
}

/// What the audio report says for one day, written for the ear: short sentences, whole words,
/// numbers said once.
///
/// A report is only ever for a single day's Daily Recovery Score. It never speaks about the
/// spread or the trend across days.
enum DailyReport {
    static func script(
        dayStart: Date,
        isScored: Bool,
        score: RecoveryScore?
    ) -> String {
        var sentences = ["Your report for \(dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day()))."]

        guard let score else {
            sentences.append(
                isScored
                    ? "This day has no score. The scan was not clear enough to read, so it is left out of your trend and your normal."
                    : "This day has not been scored yet."
            )
            return sentences.joined(separator: " ")
        }

        let band = RecoveryBand(value: score.value)
        sentences.append("Your recovery score is \(score.value). \(band.label).")

        if score.isBaselineForming {
            let needed = ScoreTuning.default.minimumScansForBaseline
            sentences.append("Your normal is still forming. This score comes from the scan alone, until you have \(needed) clear scans.")
        } else {
            sentences.append("\(normal) is your normal. \(comparison(of: score.value))")
            if let mover = score.biggestMover {
                let higher = score[deviation: mover] > 0
                sentences.append("The biggest change is \(mover.displayName.lowercased()), which is \(higher ? "higher" : "lower") than usual.")
            } else {
                sentences.append("Nothing stands out from your normal.")
            }
        }

        return sentences.joined(separator: " ")
    }

    private static var normal: Int { Int(ScoreTuning.default.atBaselineScore) }

    private static func comparison(of value: Int) -> String {
        switch value - normal {
        case 0: "This day is right at your normal."
        case 1...: "This day is \(value - normal) above your normal."
        default: "This day is \(normal - value) below your normal."
        }
    }
}
