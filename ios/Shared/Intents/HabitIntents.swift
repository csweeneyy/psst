import AppIntents
import Foundation
import SwiftData

/// Marking a habit done from a Live Activity or an alarm button.
///
/// Conforms to `LiveActivityIntent`, so the system launches the app's process
/// *without opening the app*, runs this, and returns. That is what makes the
/// Lock Screen button feel instant.
/// Marking a habit done from a Live Activity or an alarm button.
///
/// `SetValueIntent` is not decoration. A `Toggle` bound to a `SetValueIntent`
/// repaints optimistically the instant it is tapped, before `perform()` runs.
/// A plain `Button` has no equivalent, and on iOS 26 a `LiveActivityIntent`
/// always costs a background launch of the app process, which is the latency
/// floor. Optimistic repaint is the only way to hide it.
public struct CompleteHabitIntent: SetValueIntent, LiveActivityIntent {
    public static let title: LocalizedStringResource = "Complete Habit"
    public static let description = IntentDescription("Marks a habit as done for this reminder.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Done") public var value: Bool
    @Parameter(title: "Habit ID") public var habitID: String
    @Parameter(title: "Occurrence ID") public var occurrenceID: String

    public init() {}

    public init(habitID: UUID, occurrenceID: UUID) {
        self.value = true
        self.habitID = habitID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        psstLog.notice("CompleteHabitIntent fired for \(occurrenceID, privacy: .public)")
        let id = UUID(uuidString: occurrenceID)
        // Repaint first. Opening the SwiftData store on a cold app process is
        // the slow step, and the card must not wait on it.
        if let id { await NudgeActivity.resolve(occurrenceID: id) }
        await OccurrenceWriter.resolve(
            occurrenceID: id,
            habitID: UUID(uuidString: habitID),
            as: .completed
        )
        return .result()
    }
}

public struct SnoozeHabitIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Snooze Habit"
    public static let description = IntentDescription("Pushes this reminder back a few minutes.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Habit ID") public var habitID: String
    @Parameter(title: "Occurrence ID") public var occurrenceID: String

    public init() {}

    public init(habitID: UUID, occurrenceID: UUID) {
        self.habitID = habitID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        psstLog.notice("SnoozeHabitIntent fired for \(occurrenceID, privacy: .public)")
        let id = UUID(uuidString: occurrenceID)
        guard let id else { return .result() }
        let until = Date.now.addingTimeInterval(TimeInterval(FollowUp.delayMinutes * 60))
        // Repaint first: opening the store is the slow step and the card must
        // not wait on it.
        await NudgeActivity.resolve(occurrenceID: id, snoozedUntil: until)
        await FollowUp.snooze(occurrenceID: id)
        return .result()
    }
}

/// Single place that writes a response back to the shared store.
///
/// Lives here rather than in a service because both targets need it and it has
/// no dependencies beyond the store itself.
public enum OccurrenceWriter {
    @MainActor
    public static func resolve(occurrenceID: UUID?, habitID: UUID?, as status: OccurrenceStatus) {
        guard let occurrenceID else {
            psstLog.error("resolve called with no occurrence id")
            return
        }
        // The container's own `mainContext` is exactly what SwiftUI hands to
        // views as `@Environment(\.modelContext)`. Writing through a separate
        // `ModelContext` saved to the same store but left the running app's
        // `@Query` holding a stale object, so answering a nudge on the Lock
        // Screen still raised the in-app takeover on unlock.
        let context = PsstStore.shared.mainContext
        let descriptor = FetchDescriptor<HabitOccurrence>(
            predicate: #Predicate { $0.id == occurrenceID }
        )
        guard let occurrence = try? context.fetch(descriptor).first else {
            psstLog.error("no occurrence row for \(occurrenceID.uuidString, privacy: .public)")
            return
        }

        if status == .skipped {
            occurrence.snoozeCount += 1
        }
        occurrence.status = status
        occurrence.respondedAt = .now
        do {
            try context.save()
            psstLog.notice("saved \(status.rawValue, privacy: .public) for \(occurrenceID.uuidString, privacy: .public)")
            WidgetSnapshot.reload()
        } catch {
            psstLog.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
