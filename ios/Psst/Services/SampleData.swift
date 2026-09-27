import Foundation
import SwiftData

/// A month of plausible history.
///
/// Exists because every analytical surface in the app, the suggestion engine,
/// the calendar, the time-of-day chart, the weekly review, needs weeks of data
/// before it shows anything at all. A new user staring at four empty screens
/// cannot tell whether the app is any good.
enum SampleData {
    static var isForced: Bool {
        ProcessInfo.processInfo.environment["PSST_SEED"] == "1"
    }

    @MainActor
    static func install(into context: ModelContext, now: Date = .now) {
        let existing = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        guard existing.isEmpty else { return }

        let posture = Habit(
            name: "Posture check",
            nudgeText: "Psst... check your posture :)",
            intensity: .standard,
            schedule: Schedule(
                kind: .interval(minutes: 120),
                windowStartMinute: 9 * 60, windowEndMinute: 21 * 60,
                minIntervalMinutes: 60
            ),
            symbol: "figure.stand",
            tintHex: "#007AFF"
        )
        posture.nudgeVariantsRaw = [
            "shoulders back?",
            "Psst... sit up",
            "chin up, screen down",
        ].joined(separator: "\n")
        posture.notes = "Counts if I reset my shoulders, even for a second."

        let water = Habit(
            name: "Drink water",
            nudgeText: "Psst... water break",
            intensity: .gentle,
            schedule: Schedule(
                kind: .spread(count: 6, period: .day),
                windowStartMinute: 8 * 60, windowEndMinute: 20 * 60,
                minIntervalMinutes: 45
            ),
            symbol: "drop",
            tintHex: "#30B0C7"
        )
        water.nudgeVariantsRaw = "hydrate\nglass of water?"

        let gym = Habit(
            name: "Gym",
            nudgeText: "Gym. No negotiating.",
            intensity: .alarm,
            schedule: Schedule(
                kind: .fixedTimes([18 * 60]),
                weekdays: [2, 4, 6],
                minIntervalMinutes: 240
            ),
            symbol: "dumbbell",
            tintHex: "#34C759"
        )
        gym.notes = "Walking there is the hard part. Anything after that counts."

        for habit in [posture, water, gym] { context.insert(habit) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // 30 days of history. Posture and water are broadly healthy and
        // improving; the gym is reliably answered late morning and reliably
        // ignored at 6 PM, which is a pattern the advisor can actually find.
        for dayOffset in 1...30 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let recencyBonus = Double(31 - dayOffset) / 60

            for minute in [10 * 60, 13 * 60, 16 * 60, 19 * 60] {
                add(posture, day: day, minute: minute, odds: 0.58 + recencyBonus, calendar: calendar, context: context)
            }
            for minute in [9 * 60, 12 * 60, 15 * 60, 18 * 60] {
                add(water, day: day, minute: minute, odds: 0.74 + recencyBonus * 0.5, calendar: calendar, context: context)
            }
            if [2, 4, 6].contains(calendar.component(.weekday, from: day)) {
                add(gym, day: day, minute: 18 * 60, odds: 0.05, calendar: calendar, context: context)
                add(gym, day: day, minute: 11 * 60, odds: 0.95, calendar: calendar, context: context)
            }
        }

        // Today, partly answered, with a few still ahead.
        for (habit, minute, status) in todayPlan(posture: posture, water: water, gym: gym, now: now, calendar: calendar) {
            guard let date = calendar.date(byAdding: .minute, value: minute, to: today) else { continue }
            let occurrence = HabitOccurrence(scheduledAt: date, habit: habit)
            occurrence.status = status
            if status != .pending { occurrence.respondedAt = date }
            context.insert(occurrence)
        }

        try? context.save()
    }

    private static func todayPlan(
        posture: Habit, water: Habit, gym: Habit, now: Date, calendar: Calendar
    ) -> [(Habit, Int, OccurrenceStatus)] {
        let minuteNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let slots: [(Habit, Int)] = [
            (water, 9 * 60), (posture, 10 * 60), (water, 12 * 60), (posture, 13 * 60),
            (water, 15 * 60), (posture, 16 * 60), (gym, 18 * 60),
            (water, 18 * 60 + 30), (posture, 19 * 60), (water, 20 * 60),
        ]
        return slots.enumerated().map { index, slot in
            let status: OccurrenceStatus
            if slot.1 > minuteNow {
                status = .pending
            } else {
                status = index % 5 == 3 ? .skipped : .completed
            }
            return (slot.0, slot.1, status)
        }
    }

    private static func add(
        _ habit: Habit, day: Date, minute: Int, odds: Double,
        calendar: Calendar, context: ModelContext
    ) {
        guard let date = calendar.date(byAdding: .minute, value: minute, to: day) else { return }
        let occurrence = HabitOccurrence(scheduledAt: date, habit: habit)
        occurrence.status = Double.random(in: 0...1) < odds ? .completed : .missed
        occurrence.respondedAt = date
        context.insert(occurrence)
    }
}
