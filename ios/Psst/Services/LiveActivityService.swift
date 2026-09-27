import ActivityKit
import Foundation

/// The `standard` tier.
///
/// iOS 26 can start a Live Activity at a future date with the app in the
/// background, so this needs no server and no push. The Lock Screen card
/// renders Done and Snooze inline, with no long press.
nonisolated enum LiveActivityService {

    enum ServiceError: Error {
        case disabled
        case budgetRefused(Error)
    }

    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func endAll() async {
        await NudgeActivity.endAll()
    }

    /// Schedules one Live Activity per planned nudge.
    ///
    /// Apple deliberately does not publish the concurrent-activity limit, so a
    /// refusal here is expected rather than exceptional. The caller degrades
    /// the refused nudges to plain notifications.
    static func sync(
        _ nudges: [PlannedNudge],
        habits: [UUID: Habit],
        occurrenceIDs: [PlannedNudge: UUID]
    ) async -> Result<[PlannedNudge], ServiceError> {
        guard isAvailable else {
            psstLog.error("live activities are disabled for this app in Settings")
            return .failure(.disabled)
        }

        // Only clear activities that have not fired yet. Ending an `.active`
        // one would yank a card off the Lock Screen while the user is looking
        // at it, which is exactly the moment the app is supposed to be useful.
        var alive: Set<UUID> = []
        for activity in NudgeActivity.all() {
            switch activity.activityState {
            case .active, .stale:
                alive.insert(activity.attributes.occurrenceID)
            default:
                psstLog.notice(
                    "clearing \(String(describing: activity.activityState), privacy: .public) activity \(activity.id, privacy: .public)"
                )
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        var started: [PlannedNudge] = []
        for nudge in nudges {
            guard let habit = habits[nudge.habitID], nudge.fireAt > .now else { continue }
            let occurrenceID = occurrenceIDs[nudge] ?? UUID()
            // Already on screen. Re-requesting would duplicate the card.
            if alive.contains(occurrenceID) {
                started.append(nudge)
                continue
            }

            let attributes = NudgeAttributes(
                habitID: habit.id,
                occurrenceID: occurrenceID,
                habitName: habit.name,
                nudgeText: habit.nudgeText,
                symbol: habit.symbol,
                tintHex: habit.tintHex
            )
            let content = ActivityContent(
                state: NudgeAttributes.ContentState(),
                // Goes stale when the next nudge would plausibly be due, so the
                // card visibly ages instead of lying.
                staleDate: nudge.fireAt.addingTimeInterval(45 * 60)
            )
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: habit.nudgeText),
                body: "Tap Done when you have.",
                sound: .default
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: alert,
                    start: nudge.fireAt
                )
                psstLog.notice(
                    "scheduled activity \(activity.id, privacy: .public) for \(habit.name, privacy: .public) at \(nudge.fireAt, privacy: .public) state=\(String(describing: activity.activityState), privacy: .public)"
                )
                started.append(nudge)
            } catch {
                // Budget hit. Everything from here on degrades to the gentle tier.
                psstLog.error(
                    "Activity.request refused for \(habit.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return .success(started)
            }
        }
        return .success(started)
    }

    /// Clears the card as soon as the user answers, rather than letting it sit
    /// on the Lock Screen for Apple's default four hours.
    static func dismiss(occurrenceID: UUID) async {
        await NudgeActivity.resolve(occurrenceID: occurrenceID)
    }

    /// Clears anything belonging to habits that no longer exist. Without this a
    /// deleted habit keeps its scheduled card and fires for something the user
    /// cannot even see any more.
    static func dropOrphans(livingHabitIDs: Set<UUID>) async {
        for activity in NudgeActivity.all()
        where !livingHabitIDs.contains(activity.attributes.habitID) {
            psstLog.notice("ending orphaned activity \(activity.id, privacy: .public)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
