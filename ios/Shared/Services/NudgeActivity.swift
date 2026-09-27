import ActivityKit
import Foundation
import os

nonisolated public let psstLog = Logger(subsystem: "com.connorsweeney.Psst", category: "nudge")

/// Live Activity control shared by the app and the intents.
///
/// Lives in `Shared` because an intent fired from the Lock Screen has to be
/// able to close the card it was fired from, and intents are compiled into
/// both targets.
nonisolated public enum NudgeActivity {

    public static func all() -> [Activity<NudgeAttributes>] {
        Activity<NudgeAttributes>.activities
    }

    /// Acknowledges the tap on screen and schedules the card to clear.
    ///
    /// One `end` call, not an `update` followed by an `end`. Each ActivityKit
    /// call is a round trip to the system daemon, and doing two in sequence
    /// before the card changed at all is what made the button feel laggy. The
    /// final state still renders, because `end` carries content, so the user
    /// sees "Logged" for a moment before it clears.
    public static func resolve(occurrenceID: UUID, snoozedUntil: Date? = nil) async {
        let matching = all().filter { $0.attributes.occurrenceID == occurrenceID }
        psstLog.notice("resolve \(occurrenceID.uuidString, privacy: .public): \(matching.count) activities")

        let content = ActivityContent(
            state: NudgeAttributes.ContentState(answered: true, snoozedUntil: snoozedUntil),
            staleDate: nil
        )
        for activity in matching {
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(1.2)))
        }
    }

    public static func endAll() async {
        for activity in all() {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
