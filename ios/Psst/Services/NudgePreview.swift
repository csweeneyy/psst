import Foundation
import SwiftData

/// Fires one nudge shortly, through the habit's real tier.
///
/// Thin on purpose: the tier logic lives in `NudgeDelivery`, shared with
/// snooze follow-ups and queue follow-ons. Having a second copy here is how
/// previewing an Alarm habit ended up showing a banner.
enum NudgePreview {
    /// Long enough that AlarmKit and ActivityKit will both accept the date,
    /// short enough to lock the phone and still catch it.
    static let delay: TimeInterval = 30

    @MainActor
    static func fire(habit: Habit, context: ModelContext) async -> NudgeDelivery.Result {
        let fireAt = Date.now.addingTimeInterval(delay)
        let occurrence = HabitOccurrence(scheduledAt: fireAt, habit: habit)
        occurrence.isPinned = true
        occurrence.deliveryScheduled = true
        context.insert(occurrence)
        try? context.save()

        // A preview that skips the lockdown is not a preview of this habit.
        // Whatever the real nudge would do at its scheduled time, this does
        // thirty seconds from now.
        if habit.lockdownEnabled {
            LockdownService.arm(habit: habit.id, name: habit.name, at: fireAt)
        }

        return await NudgeDelivery.deliver(
            habit: habit, occurrenceID: occurrence.id, at: fireAt
        )
    }
}
