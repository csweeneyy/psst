import ActivityKit
import AlarmKit
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// Fires one nudge shortly, through the habit's actual tier.
///
/// The first version always scheduled a plain notification, so previewing an
/// Alarm habit showed a banner and told you nothing about what Alarm does.
/// The whole point of a preview is to answer "what will this feel like", which
/// a wrong tier cannot do.
enum NudgePreview {
    static let delay: TimeInterval = 10

    enum Outcome {
        case gentle
        case standard
        case alarm
        /// The tier could not be used, so it fell back to a banner.
        case degraded(Intensity, reason: String)

        var summary: String {
            switch self {
            case .gentle: "Banner in 10 seconds."
            case .standard: "Lock Screen card in 10 seconds."
            case .alarm: "Alarm in 10 seconds. It will break through silent."
            case .degraded(let intensity, let reason):
                "\(intensity.title) unavailable, sent as a banner. \(reason)"
            }
        }
    }

    @MainActor
    static func fire(habit: Habit, context: ModelContext) async -> Outcome {
        let fireAt = Date.now.addingTimeInterval(delay)
        let occurrence = HabitOccurrence(scheduledAt: fireAt, habit: habit)
        occurrence.isPinned = true
        context.insert(occurrence)
        try? context.save()

        switch habit.intensity {
        case .gentle:
            await banner(habit: habit, occurrence: occurrence, at: fireAt)
            return .gentle

        case .standard:
            if let reason = await liveActivity(habit: habit, occurrence: occurrence, at: fireAt) {
                await banner(habit: habit, occurrence: occurrence, at: fireAt)
                return .degraded(.standard, reason: reason)
            }
            return .standard

        case .alarm:
            if let reason = await alarm(habit: habit, occurrence: occurrence, at: fireAt) {
                await banner(habit: habit, occurrence: occurrence, at: fireAt)
                return .degraded(.alarm, reason: reason)
            }
            return .alarm
        }
    }

    // MARK: Tiers

    @MainActor
    private static func banner(habit: Habit, occurrence: HabitOccurrence, at fireAt: Date) async {
        await NotificationService.scheduleNow(
            habit: habit, occurrenceID: occurrence.id, fireAt: fireAt
        )
    }

    /// Returns a reason on failure, `nil` on success.
    @MainActor
    private static func liveActivity(
        habit: Habit, occurrence: HabitOccurrence, at fireAt: Date
    ) async -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are off for Psst in Settings."
        }
        let copy = habit.nudgeCopy()
        do {
            _ = try Activity.request(
                attributes: NudgeAttributes(
                    habitID: habit.id,
                    occurrenceID: occurrence.id,
                    habitName: habit.name,
                    nudgeText: copy,
                    symbol: habit.symbol,
                    tintHex: habit.tintHex
                ),
                content: ActivityContent(
                    state: NudgeAttributes.ContentState(),
                    staleDate: fireAt.addingTimeInterval(30 * 60)
                ),
                pushType: nil,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: LocalizedStringResource(stringLiteral: copy),
                    body: "Tap Done when you have.",
                    sound: .default
                ),
                start: fireAt
            )
            return nil
        } catch {
            psstLog.error("preview activity refused: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    @MainActor
    private static func alarm(
        habit: Habit, occurrence: HabitOccurrence, at fireAt: Date
    ) async -> String? {
        if AlarmService.authorization != .authorized {
            guard case .success(true) = await AlarmService.requestAuthorization() else {
                return "Alarm permission is off. Enable it in Settings."
            }
        }
        // A one-off at a fixed moment, so the preview does not disturb the
        // habit's recurring alarms.
        switch await AlarmService.scheduleOneOff(
            habit: habit, occurrenceID: occurrence.id, at: fireAt
        ) {
        case .success: return nil
        case .failure(let error): return String(describing: error)
        }
    }
}
