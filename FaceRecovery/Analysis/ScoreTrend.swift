import Foundation

/// The most recent scored days as one bar each, oldest on the left.
///
/// Like `ScoreHistogram`, only personalised scores count. Days with no scan or no usable score
/// are simply missing from the window: a gap on the chart is a day with no observation, never
/// an interpolated one.
struct ScoreTrend {
    struct Point: Identifiable, Equatable {
        let dayStart: Date
        let score: Int
        var id: Date { dayStart }
    }

    /// Calendar days shown, counting back from the most recent scored day.
    static let windowDays = 14

    /// Oldest first, so the chart reads left to right in time.
    let points: [Point]

    var latest: Point? { points.last }

    var average: Int? {
        guard !points.isEmpty else { return nil }
        return Int((Double(points.map(\.score).reduce(0, +)) / Double(points.count)).rounded())
    }

    /// One sentence for the screen and for VoiceOver, in plain words.
    var summary: String {
        guard let latest, let average else {
            return "Your daily bars appear once you have a day scored against your own normal."
        }
        let days = points.count == 1 ? "1 scored day" : "\(points.count) scored days"
        var text = "Your latest score is \(latest.score). Across the last \(Self.windowDays) days you have \(days), averaging \(average)."
        if points.count > 1 {
            switch latest.score - average {
            case 3...: text += " Your latest is above that average."
            case ...(-3): text += " Your latest is below that average."
            default: text += " Your latest is about the same as that average."
            }
        }
        return text
    }

    /// `days` must be newest first, as `DayHistory.build` returns them.
    init(days: [DayEntry], calendar: Calendar = .current) {
        let scored = days.compactMap { day -> Point? in
            guard let score = day.dailyRecoveryScore, !score.isBaselineForming else { return nil }
            return Point(dayStart: day.dayStart, score: score.value)
        }
        guard let newest = scored.first,
              let cutoff = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: newest.dayStart)
        else {
            points = []
            return
        }
        points = scored.filter { $0.dayStart >= cutoff }.reversed()
    }
}
