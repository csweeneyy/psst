import Foundation
import SwiftData
import Testing
@testable import Psst

/// A recurring AlarmKit alarm carries one baked-in intent reused for every
/// future firing, so the occurrence id inside it matches nothing. Before the
/// fallback, stopping an alarm recorded nothing at all and the in-app takeover
/// kept asking about a nudge the user had already answered.
@MainActor
@Suite("Matching an answer to an occurrence")
struct AnswerMatchingTests {

    private func store() throws -> ModelContext {
        let container = try ModelContainer(
            for: PsstStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("An unknown occurrence id falls back to the habit's nearest pending nudge")
    func fallsBackToHabit() throws {
        let context = try store()
        let habit = Habit(name: "Gym", nudgeText: "Gym", intensity: .alarm, schedule: .everyTwoHours)
        context.insert(habit)
        let due = HabitOccurrence(scheduledAt: .now.addingTimeInterval(-60), habit: habit)
        context.insert(due)
        try context.save()

        let matched = OccurrenceMatcher.match(
            occurrenceID: UUID(), habitID: habit.id, in: context, now: .now
        )
        #expect(matched?.id == due.id)
    }

    @Test("It picks the nudge nearest to now, not just any pending one")
    func picksTheNearest() throws {
        let context = try store()
        let habit = Habit(name: "Gym", nudgeText: "Gym", intensity: .alarm, schedule: .everyTwoHours)
        context.insert(habit)
        let near = HabitOccurrence(scheduledAt: .now.addingTimeInterval(-30), habit: habit)
        let far = HabitOccurrence(scheduledAt: .now.addingTimeInterval(1800), habit: habit)
        context.insert(near)
        context.insert(far)
        try context.save()

        let matched = OccurrenceMatcher.match(
            occurrenceID: nil, habitID: habit.id, in: context, now: .now
        )
        #expect(matched?.id == near.id)
    }

    @Test("It will not reach across hours for something unrelated")
    func respectsTheWindow() throws {
        let context = try store()
        let habit = Habit(name: "Gym", nudgeText: "Gym", intensity: .alarm, schedule: .everyTwoHours)
        context.insert(habit)
        context.insert(HabitOccurrence(scheduledAt: .now.addingTimeInterval(6 * 3600), habit: habit))
        try context.save()

        #expect(OccurrenceMatcher.match(
            occurrenceID: nil, habitID: habit.id, in: context, now: .now
        ) == nil)
    }

    @Test("An already answered nudge is never matched again")
    func ignoresAnswered() throws {
        let context = try store()
        let habit = Habit(name: "Gym", nudgeText: "Gym", intensity: .alarm, schedule: .everyTwoHours)
        context.insert(habit)
        let done = HabitOccurrence(scheduledAt: .now, habit: habit)
        done.status = .completed
        context.insert(done)
        try context.save()

        #expect(OccurrenceMatcher.match(
            occurrenceID: nil, habitID: habit.id, in: context, now: .now
        ) == nil)
    }

    @Test("A real id still wins over the fallback")
    func exactIdPreferred() throws {
        let context = try store()
        let habit = Habit(name: "Gym", nudgeText: "Gym", intensity: .alarm, schedule: .everyTwoHours)
        context.insert(habit)
        let nearer = HabitOccurrence(scheduledAt: .now, habit: habit)
        let asked = HabitOccurrence(scheduledAt: .now.addingTimeInterval(600), habit: habit)
        context.insert(nearer)
        context.insert(asked)
        try context.save()

        let matched = OccurrenceMatcher.match(
            occurrenceID: asked.id, habitID: habit.id, in: context, now: .now
        )
        #expect(matched?.id == asked.id)
    }
}
