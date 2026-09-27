import SwiftData
import SwiftUI
import UserNotifications

@main
struct PsstApp: App {
    @State private var coordinator = NudgeCoordinator()
    @State private var responder = NotificationResponder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(responder)
                .tint(Theme.Palette.accent)
                .preferredColorScheme(.light)
                .task {
                    UNUserNotificationCenter.current().delegate = responder
                    responder.container = PsstStore.shared
                    responder.coordinator = coordinator
                    KeyboardWarmer.warm()
                    if DebugSeed.isEnabled { DebugSeed.populate(ModelContext(PsstStore.shared)) }
                    await coordinator.requestPermissions()
                    await coordinator.resync(context: ModelContext(PsstStore.shared))
                }
        }
        // Scene bodies are not evaluated on a background intent launch, so the
        // store is only built when there is actually a window.
        .modelContainer(PsstStore.shared)
    }
}

/// Handles taps and action buttons on `gentle` tier notifications.
///
/// Separate from `NudgeCoordinator` because it must be an `NSObject` for the
/// `UNUserNotificationCenterDelegate` conformance, and mixing that into the
/// coordinator would drag Objective-C runtime concerns into scheduling.
@Observable
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    var container: ModelContainer?
    var coordinator: NudgeCoordinator?
    /// Set when the user taps the banner body rather than an action button, so
    /// the app can open straight onto a one-tap completion sheet.
    var pendingOccurrence: UUID?
    /// Set when the weekly review notification is tapped.
    var showWeeklyReview = false

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let occurrenceID = (info[NotificationService.occurrenceKey] as? String).flatMap(UUID.init)
        let habitID = (info[NotificationService.habitKey] as? String).flatMap(UUID.init)

        switch response.actionIdentifier {
        case NotificationService.completeAction:
            OccurrenceWriter.resolve(occurrenceID: occurrenceID, habitID: habitID, as: .completed)
            if let occurrenceID {
                await NudgeQueue.advance(after: occurrenceID)
            }
        case NotificationService.snoozeAction:
            if let occurrenceID {
                await FollowUp.snooze(occurrenceID: occurrenceID)
                await NudgeQueue.advance(after: occurrenceID)
            }
        case UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == WeeklyReviewService.categoryID {
                showWeeklyReview = true
                return
            }
            // Banner tap. The fast path: land on the completion sheet.
            pendingOccurrence = occurrenceID
        default:
            break
        }

        if let occurrenceID { await LiveActivityService.dismiss(occurrenceID: occurrenceID) }
        if let container, let coordinator {
            await coordinator.resync(context: ModelContext(PsstStore.shared))
        }
    }
}
