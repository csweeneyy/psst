import AppIntents
import Foundation
import SwiftData

/// Logs whatever is due right now, without opening anything.
///
/// Built for the Action button: one physical press with the screen off marks
/// the current nudge done. Deliberately a plain `AppIntent` so it runs in the
/// widget extension process rather than launching the app.
public struct CompleteNextHabitIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log the next habit"
    public static let description = IntentDescription(
        "Marks whatever nudge is currently due as done."
    )
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WidgetSnapshot.current()
        guard let occurrenceID = snapshot.occurrenceID, snapshot.isDue else {
            return .result(dialog: "Nothing due right now.")
        }
        OccurrenceWriter.resolve(
            occurrenceID: occurrenceID, habitID: snapshot.habitID, as: .completed
        )
        await NudgeActivity.resolve(occurrenceID: occurrenceID)
        WidgetSnapshot.reload()
        return .result(dialog: "\(snapshot.habitName) logged.")
    }
}
