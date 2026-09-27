import Foundation
import SwiftData

/// Populates a realistic day so the UI can be inspected without tapping
/// through setup. Only runs when `PSST_SEED=1` is in the environment, which
/// the Xcode scheme does not set.
enum DebugSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PSST_SEED"] == "1"
    }

    @MainActor
    static func populate(_ context: ModelContext) {
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
        for habit in [posture, water, gym] { context.insert(habit) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let plan: [(Habit, Int, OccurrenceStatus)] = [
            (posture, 9 * 60, .completed),
            (water, 9 * 60 + 30, .completed),
            (posture, 11 * 60, .completed),
            (water, 12 * 60, .skipped),
            (posture, 13 * 60, .completed),
            (water, 14 * 60 + 30, .pending),
            (posture, 15 * 60, .pending),
            (water, 17 * 60, .pending),
            (gym, 18 * 60, .pending),
            (posture, 19 * 60, .pending),
        ]
        for (habit, minute, status) in plan {
            guard let date = calendar.date(byAdding: .minute, value: minute, to: today) else { continue }
            let occurrence = HabitOccurrence(scheduledAt: date, habit: habit)
            occurrence.status = status
            if status != .pending { occurrence.respondedAt = date }
            context.insert(occurrence)
        }

        // A few prior days so streaks and rates are not zero.
        for dayOffset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for (habit, minute) in [(posture, 10 * 60), (posture, 14 * 60), (water, 11 * 60), (water, 16 * 60)] {
                guard let date = calendar.date(byAdding: .minute, value: minute, to: day) else { continue }
                let occurrence = HabitOccurrence(scheduledAt: date, habit: habit)
                occurrence.status = (dayOffset + minute) % 4 == 0 ? .skipped : .completed
                occurrence.respondedAt = date
                context.insert(occurrence)
            }
        }

        // A deliberate, findable pattern: the gym nudge at 6 PM is reliably
        // ignored while the same habit at 11 AM is reliably answered. Gives
        // `ScheduleAdvisor` something real to detect in a demo build.
        gym.notes = "Anything counts. Walking there is the hard part."
        for dayOffset in 1...8 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for (minute, done) in [(18 * 60, false), (11 * 60, true)] {
                guard let date = calendar.date(byAdding: .minute, value: minute, to: day) else { continue }
                let occurrence = HabitOccurrence(scheduledAt: date, habit: gym)
                occurrence.status = done ? .completed : .missed
                occurrence.respondedAt = date
                context.insert(occurrence)
            }
        }

        context.insert(ChatMessage(role: "user", text: "posture one is too often while I'm in meetings"))
        context.insert(ChatMessage(
            role: "assistant",
            text: "Pushed posture checks to every 3 hours and paused them between 1 and 3 PM on weekdays. Your 7 day completion on that one was 62%, mostly missing in that exact window, so this should help.",
            appliedSummary: "Posture check: Every 3 hours, 9 AM to 9 PM"
        ))
        try? context.save()
    }
}
