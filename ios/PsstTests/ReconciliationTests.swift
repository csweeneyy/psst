import Foundation
import Testing
@testable import Psst

private let habitA = UUID()
private let habitB = UUID()
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ minutesFromNow: Int) -> Date {
    now.addingTimeInterval(Double(minutesFromNow) * 60)
}

private func existing(
    _ habit: UUID,
    _ minutesFromNow: Int,
    pending: Bool = true,
    pinned: Bool = false
) -> SchedulingService.ExistingNudge {
    SchedulingService.ExistingNudge(
        id: UUID(), habitID: habit, scheduledAt: at(minutesFromNow),
        isPending: pending, isPinned: pinned
    )
}

@Suite("Reconciling a changed schedule")
struct ReconciliationTests {

    /// The bug: editing a habit added the new times but left the old ones on
    /// the Home screen, so the edit looked like it had done nothing.
    @Test("Rescheduling a habit clears the old times")
    func editedScheduleDropsOldOccurrences() {
        let old = [existing(habitA, 60), existing(habitA, 120), existing(habitA, 180)]
        let plan = NudgePlan(notifications: [
            PlannedNudge(habitID: habitA, fireAt: at(30)),
            PlannedNudge(habitID: habitA, fireAt: at(90)),
        ])
        let stale = SchedulingService.stale(existing: old, plan: plan, now: now)
        #expect(Set(stale) == Set(old.map(\.id)))
    }

    @Test("A time you moved by hand survives a resync")
    func pinnedOccurrencesAreKept() {
        let pinned = existing(habitA, 61, pinned: true)
        let drifting = existing(habitA, 120)
        let plan = NudgePlan(notifications: [PlannedNudge(habitID: habitA, fireAt: at(30))])
        let stale = SchedulingService.stale(existing: [pinned, drifting], plan: plan, now: now)
        #expect(stale == [drifting.id])
    }

    @Test("History is never rewritten")
    func answeredAndPastAreKept() {
        let answered = existing(habitA, 60, pending: false)
        let past = existing(habitA, -60)
        let stale = SchedulingService.stale(existing: [answered, past], plan: NudgePlan(), now: now)
        #expect(stale.isEmpty)
    }

    @Test("Editing one habit leaves another habit alone")
    func otherHabitsAreUntouched() {
        let keep = existing(habitB, 60)
        let drop = existing(habitA, 60)
        let plan = NudgePlan(notifications: [PlannedNudge(habitID: habitB, fireAt: at(60))])
        let stale = SchedulingService.stale(existing: [keep, drop], plan: plan, now: now)
        #expect(stale == [drop.id])
    }

    @Test("A sub-minute difference is the same nudge, not a new one")
    func matchingIsMinuteGranular() {
        let stored = existing(habitA, 60)
        let plan = NudgePlan(notifications: [
            PlannedNudge(habitID: habitA, fireAt: at(60).addingTimeInterval(12))
        ])
        #expect(SchedulingService.stale(existing: [stored], plan: plan, now: now).isEmpty)
    }
}

@Suite("Minute of day conversion")
struct MinuteOfDayTests {
    @Test("Round trips at minute precision, not 15 minute buckets")
    func roundTrip() {
        for minute in [0, 1, 331, 947, 1439] {
            #expect(MinuteOfDay.minutes(MinuteOfDay.date(minute)) == minute)
        }
    }
}
