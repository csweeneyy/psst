import Foundation

/// Scoring.
///
/// Two rules, both deliberate:
///
/// 1. A habit is worth its `dailyPoints` **per day**, shared across however
///    many times it fires. A habit nagging you six times a day is not worth
///    six times one that fires once, and scoring per nudge would make the
///    cheapest way to win "schedule more nudges".
/// 2. Streaks multiply, in steps rather than continuously. A smooth curve is
///    impossible to reason about; "a week is worth a quarter more" is not.
nonisolated enum PointsService {
    /// Extra per full week of streak.
    static let streakStep = 0.25
    /// Ceiling, so a long streak cannot dwarf everything else.
    static let maxMultiplier = 2.0

    static func multiplier(forStreak streak: Int) -> Double {
        min(1 + Double(streak / 7) * streakStep, maxMultiplier)
    }

    /// One habit's score for one day.
    ///
    /// Proportional to how much of that day you actually answered, so a
    /// partly-done day earns partly.
    static func score(
        habit: Habit,
        on day: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayScore {
        let start = calendar.startOfDay(for: day)
        let sameDay = habit.occurrences.filter {
            calendar.isDate($0.scheduledAt, inSameDayAs: start)
        }
        let answered = sameDay.filter { $0.status != .pending }
        let completed = sameDay.filter { $0.status == .completed }.count

        guard !answered.isEmpty, completed > 0 else {
            return DayScore(day: start, base: 0, multiplier: 1, total: 0)
        }

        let share = Double(completed) / Double(answered.count)
        let base = Int((Double(habit.dailyPoints) * share).rounded())
        let factor = multiplier(
            forStreak: HabitStatsService.streak(for: habit.occurrences, now: now, calendar: calendar)
        )
        return DayScore(
            day: start,
            base: base,
            multiplier: factor,
            total: Int((Double(base) * factor).rounded())
        )
    }

    static func today(_ habits: [Habit], now: Date = .now, calendar: Calendar = .current) -> Int {
        habits.reduce(0) { $0 + score(habit: $1, on: now, now: now, calendar: calendar).total }
    }

    /// Rolling window, oldest day first.
    static func daily(
        _ habits: [Habit], days: Int, now: Date = .now, calendar: Calendar = .current
    ) -> [DayScore] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset -> DayScore? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = habits.reduce(0) { $0 + score(habit: $1, on: day, now: now, calendar: calendar).total }
            let base = habits.reduce(0) { $0 + score(habit: $1, on: day, now: now, calendar: calendar).base }
            return DayScore(day: day, base: base, multiplier: base == 0 ? 1 : Double(total) / Double(base), total: total)
        }
    }

    static func total(_ habits: [Habit], overDays days: Int, now: Date = .now, calendar: Calendar = .current) -> Int {
        daily(habits, days: days, now: now, calendar: calendar).reduce(0) { $0 + $1.total }
    }

    /// Everything on record. Walks each habit's own history rather than a
    /// fixed window, so an old habit is not silently truncated.
    static func allTime(_ habits: [Habit], now: Date = .now, calendar: Calendar = .current) -> Int {
        var running = 0
        for habit in habits {
            let days = Set(habit.occurrences.map { calendar.startOfDay(for: $0.scheduledAt) })
            for day in days where day <= calendar.startOfDay(for: now) {
                running += score(habit: habit, on: day, now: now, calendar: calendar).total
            }
        }
        return running
    }
}
