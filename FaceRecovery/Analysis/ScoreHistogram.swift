import Foundation

/// How many days landed in each ten-point slice of the Sleep Prediction.
///
/// Only personalised scores are counted. A Baseline Forming score is read straight from Absolute
/// Signals on a different footing, so mixing it in would blur two different measures into one
/// shape.
struct ScoreHistogram {
    struct Bin: Identifiable, Equatable {
        /// Inclusive lower edge: 0, 10, ... 90.
        let lowerBound: Int
        /// Inclusive upper edge: 9, 19, ... 99, and 100 for the last bin.
        let upperBound: Int
        let count: Int
        var id: Int { lowerBound }
    }

    static let binWidth = 10

    let bins: [Bin]
    let totalDays: Int
    /// The most recent day's score, so the chart can say where "today" sits.
    let latestScore: Int?

    var latestBinLowerBound: Int? { latestScore.map(Self.lowerBound(of:)) }

    /// The busiest bin. A tie goes to the higher scores.
    var modalBin: Bin? {
        guard totalDays > 0 else { return nil }
        return bins.max { ($0.count, $0.lowerBound) < ($1.count, $1.lowerBound) }
    }

    /// One sentence for the screen and for VoiceOver, in plain words.
    var summary: String {
        guard let modalBin, totalDays > 0 else {
            return "Your chart appears once you have a day scored against your own normal."
        }
        let range = "\(modalBin.lowerBound) and \(modalBin.upperBound)"
        let days = modalBin.count == 1 ? "1 day" : "\(modalBin.count) days"
        var text = "Most often your score is between \(range) (\(days) out of \(totalDays))."
        if let latestScore {
            text += " Your latest score is \(latestScore)."
        }
        return text
    }

    /// `days` must be newest first, as `DayHistory.build` returns them.
    init(days: [DayEntry]) {
        let scores = days.compactMap { day -> Int? in
            guard let prediction = day.dailyPrediction, !prediction.isBaselineForming else { return nil }
            return prediction.value
        }
        self.init(scores: scores)
    }

    /// `scores` newest first.
    init(scores: [Int]) {
        var counts = [Int: Int]()
        for score in scores { counts[Self.lowerBound(of: score), default: 0] += 1 }
        bins = stride(from: 0, to: 100, by: Self.binWidth).map { lower in
            Bin(
                lowerBound: lower,
                upperBound: lower == 90 ? 100 : lower + Self.binWidth - 1,
                count: counts[lower] ?? 0
            )
        }
        totalDays = scores.count
        latestScore = scores.first
    }

    /// 100 belongs with 90-100 rather than opening an eleventh bin.
    static func lowerBound(of score: Int) -> Int {
        min(max(score, 0), 99) / binWidth * binWidth
    }
}
