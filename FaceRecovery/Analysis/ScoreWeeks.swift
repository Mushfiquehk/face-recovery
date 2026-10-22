import Foundation

/// This calendar week and last week of Sleep Predictions, for two line plots that share one
/// scale so they can be compared at a glance.
///
/// Like `ScoreHistogram`, only personalised scores count. A day with no usable score is a gap,
/// never an interpolated value, so the line is drawn in separate runs that break at a gap.
struct ScoreWeeks {
    struct Point: Identifiable, Equatable {
        let dayStart: Date
        let score: Int
        var id: Date { dayStart }
    }

    struct Week {
        let title: String
        /// All seven days, first day of the week first, including days still to come.
        let days: [Date]
        /// Oldest first.
        let points: [Point]
        /// Consecutive scored days. A missing day splits the line instead of being bridged.
        let runs: [[Point]]

        var average: Int? {
            guard !points.isEmpty else { return nil }
            return Int((Double(points.map(\.score).reduce(0, +)) / Double(points.count)).rounded())
        }

        var start: Date { days[0] }
        var end: Date { days[6] }
    }

    let thisWeek: Week
    let lastWeek: Week
    /// One vertical scale for both plots, snapped to tens so the labels stay round.
    let yDomain: ClosedRange<Int>
    let yTicks: [Int]

    var hasScores: Bool { !thisWeek.points.isEmpty || !lastWeek.points.isEmpty }

    /// How this week's average compares with last week's. Nil unless both weeks have scores.
    var trend: Trend? {
        guard let now = thisWeek.average, let before = lastWeek.average else { return nil }
        let change = now - before
        switch change {
        case 3...: return .up(by: change)
        case ...(-3): return .down(by: -change)
        default: return .steady
        }
    }

    enum Trend: Equatable {
        case up(by: Int)
        case down(by: Int)
        case steady
    }

    /// One sentence for the screen and for VoiceOver, in plain words.
    var summary: String {
        guard hasScores else {
            return "Your weekly lines appear once you have a day scored against your own normal."
        }
        guard let average = thisWeek.average else {
            return "No scores yet this week. Last week averaged \(lastWeek.average ?? 0)."
        }
        switch trend {
        case .up(let by): return "This week averages \(average), which is \(by) higher than last week."
        case .down(let by): return "This week averages \(average), which is \(by) lower than last week."
        case .steady: return "This week averages \(average), about the same as last week."
        case nil: return "This week averages \(average). There are no scores from last week to compare with."
        }
    }

    /// `days` must be newest first, as `DayHistory.build` returns them.
    init(days: [DayEntry], now: Date = .now, calendar: Calendar = .current) {
        let scored = days.compactMap { day -> Point? in
            guard let prediction = day.dailyPrediction, !prediction.isBaselineForming else { return nil }
            return Point(dayStart: day.dayStart, score: prediction.value)
        }
        .reversed()

        let thisStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let lastStart = calendar.date(byAdding: .day, value: -7, to: thisStart) ?? thisStart

        thisWeek = Self.week("This week", start: thisStart, scored: Array(scored), calendar: calendar)
        lastWeek = Self.week("Last week", start: lastStart, scored: Array(scored), calendar: calendar)

        let (domain, ticks) = Self.scale(
            for: (thisWeek.points + lastWeek.points).map(\.score)
        )
        yDomain = domain
        yTicks = ticks
    }

    private static func week(_ title: String, start: Date, scored: [Point], calendar: Calendar) -> Week {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let first = days.first ?? start
        let last = days.last ?? start
        let points = scored.filter { $0.dayStart >= first && $0.dayStart <= last }

        var runs = [[Point]]()
        for point in points {
            if let previous = runs.last?.last,
               calendar.date(byAdding: .day, value: 1, to: previous.dayStart) == point.dayStart {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return Week(title: title, days: days, points: points, runs: runs)
    }

    /// A vertical range that fits the scores with room for their labels, always includes the
    /// user's normal, and never shrinks below 30 points so a quiet week is not exaggerated.
    static func scale(for scores: [Int]) -> (ClosedRange<Int>, [Int]) {
        let normal = Int(SleepModel.bundled.startingValue.rounded())
        let low = (scores + [normal]).min() ?? normal
        let high = (scores + [normal]).max() ?? normal

        var lower = max(0, Int((Double(low - 5) / 10).rounded(.down)) * 10)
        var upper = min(100, Int((Double(high + 8) / 10).rounded(.up)) * 10)

        while upper - lower < 30 {
            if upper < 100 { upper += 10 } else if lower > 0 { lower -= 10 } else { break }
        }

        let step = upper - lower > 40 ? 20 : 10
        if step == 20 {
            lower = lower / 20 * 20
            upper = min(100, Int((Double(upper) / 20).rounded(.up)) * 20)
        }
        return (lower...upper, Array(stride(from: lower, through: upper, by: step)))
    }
}
