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

    /// Replaces every pending request with the new plan.
    ///
    /// Wholesale replacement rather than diffing, because the 64-slot budget
    /// means a stale request is actively harmful: it occupies a slot a sooner
    /// reminder needs.
    static func sync(
        _ nudges: [PlannedNudge],
        habits: [UUID: Habit],
        occurrenceIDs: [PlannedNudge: UUID],
        on center: UNUserNotificationCenter
    ) async -> Result<Int, Error> {
        // Everything except the requests this sync does not own: snooze
        // follow-ups, scheduled by whichever process handled the tap, and the
        // repeating weekly review.
        let preserved = [FollowUp.identifierPrefix, NudgeQueue.identifierPrefix, "psst.review."]
        let pending = await center.pendingNotificationRequests()
        let replaceable = pending
            .map(\.identifier)
            .filter { identifier in !preserved.contains { identifier.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: replaceable)

        var scheduled = 0
        for nudge in nudges.prefix(SchedulingService.pendingNotificationLimit) {
            guard let habit = habits[nudge.habitID] else { continue }

            let content = UNMutableNotificationContent()
            content.title = habit.nudgeCopy()
            content.body = "Tap to log it."
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.interruptionLevel = .timeSensitive
            content.userInfo = [
                habitKey: habit.id.uuidString,
                occurrenceKey: (occurrenceIDs[nudge] ?? UUID()).uuidString,
            ]

            let interval = nudge.fireAt.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: "psst.\(habit.id.uuidString).\(Int(nudge.fireAt.timeIntervalSince1970))",
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                return .failure(error)
            }
        }
        return .success(scheduled)
    }
}
