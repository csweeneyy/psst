import Foundation
import SwiftData
import UserNotifications

/// Snoozing has to actually bring the nudge back.
///
/// Marking the occurrence skipped and stopping there meant "Later" was a
/// silent way to cancel. A follow-up is scheduled directly from whichever
/// process handled the tap, because the Lock Screen path runs with the app in
/// the background and cannot wait for a full resync.
nonisolated public enum FollowUp {
    public static let delayMinutes = 10
    /// After this many snoozes the nudge stops coming back. Three "laters" is
    /// an answer.
    public static let maxSnoozes = 3

    public static let identifierPrefix = "psst.followup."

    public static func identifier(for occurrenceID: UUID) -> String {
        identifierPrefix + occurrenceID.uuidString
    }

    /// Marks the original skipped and queues the next attempt.
    /// Returns the follow-up's fire date, if one was created.
    /// Takes the container, not the context. `ModelContext` is not `Sendable`,
    /// so handing one across an actor boundary does not compile; the context is
    /// resolved here, already on the main actor.
    @MainActor
    @discardableResult
    public static func snooze(
        occurrenceID: UUID,
        container: ModelContainer = PsstStore.shared,
        now: Date = .now,
        center: UNUserNotificationCenter = .current()
    ) async -> Date? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<HabitOccurrence>(
            predicate: #Predicate { $0.id == occurrenceID }
        )
        guard let original = try? context.fetch(descriptor).first,
              let habit = original.habit else { return nil }

        let attempts = original.snoozeCount + 1
        original.snoozeCount = attempts
        original.status = .skipped
        original.respondedAt = now

        guard attempts <= maxSnoozes else {
            psstLog.notice("snooze limit reached for \(habit.name, privacy: .public)")
            try? context.save()
            return nil
        }

        let fireAt = now.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let followUp = HabitOccurrence(scheduledAt: fireAt, habit: habit)
        followUp.isPinned = true
        followUp.isFollowUp = true
        followUp.snoozeCount = attempts
        context.insert(followUp)
        try? context.save()

        await schedule(followUp: followUp, habit: habit, at: fireAt, center: center)
        WidgetSnapshot.reload()
        psstLog.notice("snoozed \(habit.name, privacy: .public) to \(fireAt, privacy: .public)")
        return fireAt
    }

    /// A plain notification regardless of the habit's tier. A follow-up has to
    /// survive the app being suspended, and this is the one path that needs no
    /// coordinator and no extra budget juggling.
    @MainActor
    private static func schedule(
        followUp: HabitOccurrence,
        habit: Habit,
        at fireAt: Date,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = habit.nudgeCopy()
        content.body = "Snoozed. Still owed."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.identifier
        content.interruptionLevel = habit.intensity == .gentle ? .active : .timeSensitive
        content.userInfo = [
            NotificationCategory.habitKey: habit.id.uuidString,
            NotificationCategory.occurrenceKey: followUp.id.uuidString,
        ]

        let interval = max(fireAt.timeIntervalSinceNow, 1)
        let request = UNNotificationRequest(
            identifier: identifier(for: followUp.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(request)
    }
}

/// Category identifiers, shared so the intents and the app agree without the
/// intents having to import the app-only notification service.
nonisolated public enum NotificationCategory {
    public static let identifier = "PSST_NUDGE"
    public static let complete = "PSST_COMPLETE"
    public static let snooze = "PSST_SNOOZE"
    public static let habitKey = "habitID"
    public static let occurrenceKey = "occurrenceID"
}
