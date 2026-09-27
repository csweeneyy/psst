import Foundation
import UserNotifications

/// The `gentle` tier.
///
/// Action buttons here only appear once the banner is expanded, which Apple
/// provides no API to change. We compensate by making the banner tap itself
/// land on a one-tap completion sheet.
nonisolated enum NotificationService {
    static let categoryID = NotificationCategory.identifier
    static let completeAction = NotificationCategory.complete
    static let snoozeAction = NotificationCategory.snooze
    static let habitKey = NotificationCategory.habitKey
    static let occurrenceKey = NotificationCategory.occurrenceKey

    static func registerCategories(on center: UNUserNotificationCenter) {
        // "Done" is deliberately first: on Apple Watch, Double Tap fires the
        // first non-destructive action, which completes a habit with no screen
        // contact at all.
        let done = UNNotificationAction(
            identifier: completeAction,
            title: "Done",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: snoozeAction,
            title: "Later (\(FollowUp.delayMinutes)m)",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let review = UNNotificationCategory(
            identifier: WeeklyReviewService.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, review])
    }

    static func requestAuthorization(on center: UNUserNotificationCenter) async -> Result<Bool, Error> {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .providesAppNotificationSettings]
            )
            return .success(granted)
        } catch {
            return .failure(error)
        }
    }

    /// Deterministic, so the same nudge always maps to the same request and a
    /// re-sync can recognise what is already scheduled.
    static func identifier(habitID: UUID, fireAt: Date) -> String {
        "psst.\(habitID.uuidString).\(Int(fireAt.timeIntervalSince1970 / 60))"
    }

    /// Reconciles pending requests with the plan.
    ///
    /// Diffs rather than clearing and rebuilding. The old version removed
    /// everything first, which left a window where the app owned no scheduled
    /// notifications at all; if iOS suspended it there, nothing ever fired.
    /// Rescheduling a nudge and immediately locking the phone hit exactly that.
    static func sync(
        _ nudges: [PlannedNudge],
        habits: [UUID: Habit],
        occurrenceIDs: [PlannedNudge: UUID],
        on center: UNUserNotificationCenter
    ) async -> Result<Int, Error> {
        var wanted: [String: UNNotificationRequest] = [:]
        for nudge in nudges.prefix(SchedulingService.pendingNotificationLimit) {
            guard let habit = habits[nudge.habitID], nudge.fireAt.timeIntervalSinceNow > 0 else { continue }
            let id = identifier(habitID: habit.id, fireAt: nudge.fireAt)
            wanted[id] = request(
                id: id,
                habit: habit,
                occurrenceID: occurrenceIDs[nudge] ?? UUID(),
                fireAt: nudge.fireAt
            )
        }

        // Requests this sync does not own: snooze follow-ups, queue follow-ons,
        // and the repeating weekly review.
        let preserved = [FollowUp.identifierPrefix, NudgeQueue.identifierPrefix, "psst.review."]
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let existing = Set(pending)

        let obsolete = pending.filter { identifier in
            preserved.contains { identifier.hasPrefix($0) } == false && wanted[identifier] == nil
        }
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }

        // Add the missing ones first, so the app is never briefly holding less
        // than it did a moment ago.
        for (id, request) in wanted where !existing.contains(id) {
            do {
                try await center.add(request)
            } catch {
                return .failure(error)
            }
        }
        return .success(wanted.count)
    }

    private static func request(
        id: String, habit: Habit, occurrenceID: UUID, fireAt: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = habit.nudgeCopy()
        content.body = "Tap to log it."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.interruptionLevel = habit.intensity == .gentle ? .active : .timeSensitive
        content.userInfo = [
            habitKey: habit.id.uuidString,
            occurrenceKey: occurrenceID.uuidString,
        ]
        return UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(fireAt.timeIntervalSinceNow, 1), repeats: false
            )
        )
    }
}
