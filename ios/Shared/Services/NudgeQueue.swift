import Foundation
import SwiftData
import UserNotifications

/// Keeps a pile-up moving.
///
/// When several habits want the same moment, the scheduler stakes them out
/// back to back and tags them with a shared group. Every one of them is
/// pre-scheduled with the OS, so nothing here is load-bearing for delivery:
/// if the app never runs again, they all still fire at their staggered slots.
///
/// What this adds is pace. Answering one pulls the next forward so it arrives
/// immediately rather than making you wait out the gap, which is what turns a
/// collision into a queue rather than a stutter.
nonisolated public enum NudgeQueue {
    /// How soon the next one arrives after you answer its predecessor.
    public static let followOnDelay: TimeInterval = 3

    public static let identifierPrefix = "psst.queued."

    /// The next unanswered nudge behind the one just resolved, if any.
    @MainActor
    public static func next(after occurrenceID: UUID, context: ModelContext) -> HabitOccurrence? {
        let descriptor = FetchDescriptor<HabitOccurrence>(
            predicate: #Predicate { $0.id == occurrenceID }
        )
        guard let answered = try? context.fetch(descriptor).first,
              let group = answered.queueGroup else { return nil }

        let all = (try? context.fetch(FetchDescriptor<HabitOccurrence>())) ?? []
        return all
            .filter {
                $0.queueGroup == group
                    && $0.status == .pending
                    && $0.queuePosition > answered.queuePosition
                    && $0.habit != nil
            }
            .min { $0.queuePosition < $1.queuePosition }
    }

    /// Pulls the next one in the group forward to arrive now.
    ///
    /// Returns it so an open app can raise its takeover immediately rather
    /// than waiting for a notification it will never receive in foreground.
    /// Takes the container, not the context: `ModelContext` is not `Sendable`
    /// and cannot cross an actor boundary.
    @MainActor
    @discardableResult
    public static func advance(
        after occurrenceID: UUID,
        container: ModelContainer = PsstStore.shared,
        center: UNUserNotificationCenter = .current()
    ) async -> UUID? {
        guard PsstStore.isDegraded == false else { return nil }
        let context = container.mainContext
        guard let follower = next(after: occurrenceID, context: context),
              let habit = follower.habit else { return nil }

        // Already due or imminent: leave its own alert to fire.
        let wait = follower.scheduledAt.timeIntervalSinceNow
        guard wait > followOnDelay else { return follower.id }

        let fireAt = Date.now.addingTimeInterval(followOnDelay)
        follower.scheduledAt = fireAt
        follower.isPinned = true
        try? context.save()

        await schedule(follower, habit: habit, at: fireAt, center: center)
        psstLog.notice(
            "advanced queued \(habit.name, privacy: .public) to \(fireAt, privacy: .public)"
        )
        return follower.id
    }

    /// A plain notification regardless of tier.
    ///
    /// A follow-on lands seconds from now, and neither a scheduled Live
    /// Activity nor an AlarmKit alarm can be created that close to its fire
    /// time reliably. Getting the nudge in front of the user matters more
    /// than honouring its tier for this one arrival.
    @MainActor
    private static func schedule(
        _ occurrence: HabitOccurrence,
        habit: Habit,
        at fireAt: Date,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = habit.nudgeCopy()
        content.body = "Next one."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.identifier
        content.interruptionLevel = habit.intensity == .gentle ? .active : .timeSensitive
        content.userInfo = [
            NotificationCategory.habitKey: habit.id.uuidString,
            NotificationCategory.occurrenceKey: occurrence.id.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: identifierPrefix + occurrence.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(fireAt.timeIntervalSinceNow, 1), repeats: false
            )
        )
        try? await center.add(request)
    }
}
