import Foundation

nonisolated struct HabitStats: Sendable {
    var completionRate: Double
    var streak: Int
    var completed: Int
    var total: Int
}

/// One hour of the day, with how reliably nudges at that hour get answered.
nonisolated struct HourSlice: Sendable, Identifiable {
    var hour: Int
    var completed: Int
    var answered: Int
    var id: Int { hour }

    var rate: Double { answered == 0 ? 0 : Double(completed) / Double(answered) }
    var hasData: Bool { answered > 0 }
}

/// A day in the recent strip.
nonisolated struct DaySlice: Sendable, Identifiable {
    var date: Date
    var completed: Int
    var answered: Int
    var scheduled: Int
    var id: Date { date }

    var rate: Double { answered == 0 ? 0 : Double(completed) / Double(answered) }
}

/// Pure functions over occurrences. No storage, no side effects, so the Habits
/// tab and the assistant snapshot compute identical numbers.
nonisolated enum HabitStatsService {

    static func stats(for occurrences: [HabitOccurrence], days: Int, now: Date = .now, calendar: Calendar = .current) -> HabitStats {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        let window = occurrences.filter { $0.scheduledAt >= cutoff && $0.scheduledAt <= now }
        let answered = window.filter { $0.status != .pending }
        let completed = window.filter { $0.status == .completed }.count
        let rate = answered.isEmpty ? 0 : Double(completed) / Double(answered.count)
        return HabitStats(
            completionRate: rate,
            streak: streak(for: occurrences, now: now, calendar: calendar),
            completed: completed,
            total: answered.count
        )
    }

    /// Consecutive days, walking backwards, on which at least one occurrence was
    /// completed. Days with no scheduled occurrence do not break the streak.
    static func streak(for occurrences: [HabitOccurrence], now: Date = .now, calendar: Calendar = .current) -> Int {
        var byDay: [Date: [OccurrenceStatus]] = [:]
        for occurrence in occurrences where occurrence.scheduledAt <= now {
            byDay[calendar.startOfDay(for: occurrence.scheduledAt), default: []].append(occurrence.status)
        }

        var streak = 0
        var day = calendar.startOfDay(for: now)
        while let statuses = byDay[day] {
            if statuses.contains(.completed) {
                streak += 1
            } else if statuses.contains(where: { $0 == .missed || $0 == .skipped }) {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Which hours of the day actually get answered. Index 0 is midnight.
    static func hourlyResponseRate(for occurrences: [HabitOccurrence], calendar: Calendar = .current) -> [Double] {
        hourly(for: occurrences, calendar: calendar).map(\.rate)
    }

    /// Same data with the counts kept, so a 1-of-1 hour can be told apart from
    /// a 40-of-40 hour. The difference matters when suggesting a move.
    static func hourly(for occurrences: [HabitOccurrence], calendar: Calendar = .current) -> [HourSlice] {
        var completed = [Int](repeating: 0, count: 24)
        var answered = [Int](repeating: 0, count: 24)
        for occurrence in occurrences where occurrence.status != .pending {
            let hour = calendar.component(.hour, from: occurrence.scheduledAt)
            answered[hour] += 1
            if occurrence.status == .completed { completed[hour] += 1 }
        }
        return (0..<24).map {
            HourSlice(hour: $0, completed: completed[$0], answered: answered[$0])
        }
    }

    /// The last `days` days, oldest first, for the recent activity strip.
    static func daily(
        for occurrences: [HabitOccurrence],
        days: Int = 14,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DaySlice] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: (completed: Int, answered: Int, scheduled: Int)] = [:]
        for occurrence in occurrences {
            let day = calendar.startOfDay(for: occurrence.scheduledAt)
            var bucket = buckets[day] ?? (0, 0, 0)
            bucket.scheduled += 1
            if occurrence.status != .pending { bucket.answered += 1 }
            if occurrence.status == .completed { bucket.completed += 1 }
            buckets[day] = bucket
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let bucket = buckets[day] ?? (0, 0, 0)
            return DaySlice(
                date: day, completed: bucket.completed,
                answered: bucket.answered, scheduled: bucket.scheduled
            )
        }
    }

    /// Coarser buckets for questions that reach past the daily window.
    /// `label` is the bucket's start date in `YYYY-MM-DD`.
    static func buckets(
        for occurrences: [HabitOccurrence],
        component: Calendar.Component,
        count: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(label: Date, completed: Int, answered: Int)] {
        guard let currentStart = calendar.dateInterval(of: component, for: now)?.start else { return [] }

        var tallies: [Date: (Int, Int)] = [:]
        for occurrence in occurrences where occurrence.status != .pending {
            guard let start = calendar.dateInterval(of: component, for: occurrence.scheduledAt)?.start
            else { continue }
            var bucket = tallies[start] ?? (0, 0)
            bucket.1 += 1
            if occurrence.status == .completed { bucket.0 += 1 }
            tallies[start] = bucket
        }

        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: component, value: -offset, to: currentStart)
            else { return nil }
            guard let bucket = tallies[start], bucket.1 > 0 else { return nil }
            return (start, bucket.0, bucket.1)
        }
    }

    /// Every day on record, for a specific range the assistant asked about.
    static func range(
        for occurrences: [HabitOccurrence],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [DaySlice] {
        var buckets: [Date: (completed: Int, answered: Int, scheduled: Int)] = [:]
        for occurrence in occurrences {
            let day = calendar.startOfDay(for: occurrence.scheduledAt)
            guard day >= calendar.startOfDay(for: from), day <= calendar.startOfDay(for: to) else { continue }
            var bucket = buckets[day] ?? (0, 0, 0)
            bucket.scheduled += 1
            if occurrence.status != .pending { bucket.answered += 1 }
            if occurrence.status == .completed { bucket.completed += 1 }
            buckets[day] = bucket
        }
        return buckets
            .map { DaySlice(date: $0.key, completed: $0.value.completed, answered: $0.value.answered, scheduled: $0.value.scheduled) }
            .sorted { $0.date < $1.date }
    }

    /// The earliest thing on record, so the assistant knows how far back to look.
    static func firstRecord(for occurrences: [HabitOccurrence]) -> Date? {
        occurrences.map(\.scheduledAt).min()
    }

    /// The best run this habit has ever had.
    static func longestStreak(
        for occurrences: [HabitOccurrence],
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(
            occurrences
                .filter { $0.status == .completed }
                .map { calendar.startOfDay(for: $0.scheduledAt) }
        ).sorted()
        guard !days.isEmpty else { return 0 }

        var best = 1
        var run = 1
        for (previous, current) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    /// Whole days since the habit was created, minimum 1.
    static func daysActive(since created: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        max((calendar.dateComponents([.day], from: calendar.startOfDay(for: created), to: now).day ?? 0) + 1, 1)
    }
}
