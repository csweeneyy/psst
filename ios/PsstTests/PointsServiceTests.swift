import Foundation
import SwiftData
import Testing
@testable import Psst

@MainActor
@Suite("Points")
struct PointsServiceTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: PsstStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// `day` 0 is today; statuses are applied in order across that day.
    @discardableResult
    private func habit(
        in context: ModelContext,
        worth: Int,
        history: [(dayOffset: Int, statuses: [OccurrenceStatus])],
        now: Date
    ) -> Habit {
        let habit = Habit(
            name: "H", nudgeText: "n", intensity: .standard, schedule: .everyTwoHours
        )
        habit.dailyPoints = worth
        context.insert(habit)
        for entry in history {
            guard let day = calendar.date(byAdding: .day, value: -entry.dayOffset, to: calendar.startOfDay(for: now))
            else { continue }
            for (index, status) in entry.statuses.enumerated() {
                let at = day.addingTimeInterval(TimeInterval(3600 * (9 + index)))
                let occurrence = HabitOccurrence(scheduledAt: at, habit: habit)
                occurrence.status = status
                context.insert(occurrence)
            }
        }
        try? context.save()
        return habit
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 20))!
    }

    @Test("A fully answered day is worth the habit's full value")
    func fullDayScoresFull() throws {
        let context = try context()
        let h = habit(in: context, worth: 10, history: [(0, [.completed, .completed])], now: now)
        #expect(PointsService.score(habit: h, on: now, now: now, calendar: calendar).base == 10)
    }

    @Test("A partly answered day earns proportionally")
    func partialDayScoresPartially() throws {
        let context = try context()
        let h = habit(in: context, worth: 10, history: [(0, [.completed, .missed, .missed, .completed])], now: now)
        // Two of four answered nudges completed.
        #expect(PointsService.score(habit: h, on: now, now: now, calendar: calendar).base == 5)
    }

    @Test("Firing more often does not earn more")
    func frequencyDoesNotInflate() throws {
        let context = try context()
        let chatty = habit(in: context, worth: 10, history: [(0, Array(repeating: .completed, count: 8))], now: now)
        let quiet = habit(in: context, worth: 10, history: [(0, [.completed])], now: now)
        #expect(
            PointsService.score(habit: chatty, on: now, now: now, calendar: calendar).total
                == PointsService.score(habit: quiet, on: now, now: now, calendar: calendar).total
        )
    }

    @Test("Streaks multiply in weekly steps, and are capped")
    func streakMultiplier() {
        #expect(PointsService.multiplier(forStreak: 0) == 1.0)
        #expect(PointsService.multiplier(forStreak: 6) == 1.0)
        #expect(PointsService.multiplier(forStreak: 7) == 1.25)
        #expect(PointsService.multiplier(forStreak: 21) == 1.75)
        // Capped, so a long streak cannot dwarf everything else.
        #expect(PointsService.multiplier(forStreak: 200) == PointsService.maxMultiplier)
    }

    @Test("A streak actually raises the day's total")
    func streakAppliesToScore() throws {
        let context = try context()
        let history = (0..<10).map { (dayOffset: $0, statuses: [OccurrenceStatus.completed]) }
        let h = habit(in: context, worth: 10, history: history, now: now)
        let score = PointsService.score(habit: h, on: now, now: now, calendar: calendar)
        #expect(score.base == 10)
        #expect(score.multiplier > 1, "ten straight days should be past the first weekly step")
        #expect(score.total > score.base)
    }

    @Test("A day with nothing answered scores nothing, not a negative")
    func emptyDayScoresZero() throws {
        let context = try context()
        let h = habit(in: context, worth: 25, history: [(0, [.missed, .missed])], now: now)
        #expect(PointsService.score(habit: h, on: now, now: now, calendar: calendar).total == 0)
    }

    @Test("Priority maps to a value and back")
    func priorityRoundTrips() {
        for priority in HabitPriority.allCases {
            #expect(HabitPriority.nearest(to: priority.points) == priority)
        }
        // An arbitrary number from the assistant still resolves sensibly.
        #expect(HabitPriority.nearest(to: 22) == .high)
        #expect(HabitPriority.nearest(to: 6) == .low)
    }
}
