import ActivityKit
import AlarmKit
import Foundation
import SwiftData
import UserNotifications

/// Delivers exactly one nudge, at one moment, through its habit's tier.
///
/// Exists because three separate paths were quietly ignoring the tier and
/// sending a plain banner: the preview, snooze follow-ups, and queue
/// follow-ons. Picking a tier per habit is the entire product, so every path
/// that puts a nudge in front of the user has to honour it. One function, used
/// by all of them.
nonisolated public enum NudgeDelivery {
    /// A scheduled Live Activity needs lead time, and AlarmKit will not accept
    /// a date this close either. Below this, deliver as a banner.
    public static let minimumLead: TimeInterval = 25

    public enum Result: Sendable {
        case delivered(Intensity)
        /// The tier could not be used, so it went out as a banner.
        case degraded(Intensity, reason: String)

        public var summary: String {
            switch self {
            case .delivered(.gentle): "Banner on its way."
            case .delivered(.standard): "Lock Screen card on its way."
            case .delivered(.alarm): "Alarm on its way. It will break through silent."
            case .degraded(let tier, let reason): "\(tier.title) unavailable, sent as a banner. \(reason)"
            }
        }
    }

    @MainActor
    @discardableResult
    public static func deliver(
        habit: Habit,
        occurrenceID: UUID,
        at fireAt: Date,
        body: String = "Tap to log it."
    ) async -> Result {
        let lead = fireAt.timeIntervalSinceNow

        switch habit.intensity {
        case .gentle:
            await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
            return .delivered(.gentle)

        case .standard:
            guard lead >= minimumLead else {
                await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
                return .degraded(.standard, reason: "Too soon to schedule a Lock Screen card.")
            }
            if let reason = await LiveActivityService.scheduleOne(
                habit: habit, occurrenceID: occurrenceID, at: fireAt
            ) {
                await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
                return .degraded(.standard, reason: reason)
            }
            return .delivered(.standard)

        case .alarm:
            guard lead >= minimumLead else {
                await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
                return .degraded(.alarm, reason: "Too soon to schedule an alarm.")
            }
            if AlarmService.authorization != .authorized {
                guard case .success(true) = await AlarmService.requestAuthorization() else {
                    await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
                    return .degraded(.alarm, reason: "Alarm permission is off. Enable it in Settings.")
                }
            }
            switch await AlarmService.scheduleOneOff(
                habit: habit, occurrenceID: occurrenceID, at: fireAt
            ) {
            case .success:
                return .delivered(.alarm)
            case .failure(let error):
                await banner(habit: habit, occurrenceID: occurrenceID, at: fireAt, body: body)
                return .degraded(.alarm, reason: String(describing: error))
            }
        }
    }

    @MainActor
    private static func banner(
        habit: Habit, occurrenceID: UUID, at fireAt: Date, body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = habit.nudgeCopy()
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.identifier
        content.interruptionLevel = habit.intensity == .gentle ? .active : .timeSensitive
        content.userInfo = [
            NotificationCategory.habitKey: habit.id.uuidString,
            NotificationCategory.occurrenceKey: occurrenceID.uuidString,
        ]
        let request = UNNotificationRequest(
            identifier: NudgeQueue.identifierPrefix + occurrenceID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(fireAt.timeIntervalSinceNow, 1), repeats: false
            )
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
