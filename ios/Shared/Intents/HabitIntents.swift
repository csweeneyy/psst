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
        let hinted = UUID(uuidString: occurrenceID)
        // Repaint first. Opening the SwiftData store on a cold app process is
        // the slow step, and the card must not wait on it.
        if let hinted { await NudgeActivity.resolve(occurrenceID: hinted) }
        // The resolved id, not the hint: a recurring alarm's baked-in id
        // matches nothing, and the queue has to advance from the real row.
        let resolved = await OccurrenceWriter.resolveReturningID(
            occurrenceID: hinted,
            habitID: UUID(uuidString: habitID),
            as: .completed
        )
        if let resolved {
            await NudgeActivity.resolve(occurrenceID: resolved)
            await NudgeQueue.advance(after: resolved)
        }
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
        let hinted = UUID(uuidString: occurrenceID)
        let until = Date.now.addingTimeInterval(TimeInterval(FollowUp.delayMinutes * 60))
        if let hinted { await NudgeActivity.resolve(occurrenceID: hinted, snoozedUntil: until) }

        // Resolve first so a recurring alarm's unmatched id still finds a row,
        // then snooze that row. `snooze` re-marks it, which is harmless.
        guard let resolved = await OccurrenceWriter.resolveReturningID(
            occurrenceID: hinted,
            habitID: UUID(uuidString: habitID),
            as: .pending
        ) else { return .result() }

        await NudgeActivity.resolve(occurrenceID: resolved, snoozedUntil: until)
        await FollowUp.snooze(occurrenceID: resolved)
        await NudgeQueue.advance(after: resolved)
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
        resolveReturningID(occurrenceID: occurrenceID, habitID: habitID, as: status)
    }

    /// Resolves an answer, returning the occurrence it actually landed on.
    ///
    /// The id is a hint, not a guarantee. AlarmKit alarms recur, so the intent
    /// baked into one is reused for every future firing and cannot carry a
    /// real occurrence id. When the id matches nothing, fall back to the
    /// habit's nearest pending occurrence. Without this the alarm tier
    /// recorded nothing at all and the in-app takeover kept asking again.
    @MainActor
    @discardableResult
    public static func resolveReturningID(
        occurrenceID: UUID?,
        habitID: UUID?,
        as status: OccurrenceStatus,
        now: Date = .now
    ) -> UUID? {
        guard PsstStore.isDegraded == false else {
            // Locked device, group store unreadable. Writing here would look
            // like success and drop the answer. The nudge stays pending and
            // gets answered again rather than being silently lost.
            psstLog.error("refusing to record an answer against a scratch store")
            return nil
        }
        let context = PsstStore.shared.mainContext
        guard let occurrence = OccurrenceMatcher.match(
            occurrenceID: occurrenceID, habitID: habitID, in: context, now: now
        ) else {
            psstLog.error("no occurrence matched this answer")
            return nil
        }

        if status == .skipped { occurrence.snoozeCount += 1 }
        occurrence.status = status
        occurrence.respondedAt = now
        do {
            try context.save()
            psstLog.notice("saved \(status.rawValue, privacy: .public) for \(occurrence.id.uuidString, privacy: .public)")
            WidgetSnapshot.reload()
        } catch {
            psstLog.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
        return occurrence.id
    }

    @MainActor
    private static func legacy(occurrenceID: UUID?, habitID: UUID?, as status: OccurrenceStatus) {
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


/// Decides which occurrence an answer belongs to.
///
/// Split out from `OccurrenceWriter` so the rule can be tested against an
/// in-memory store without dragging in App Intents.
nonisolated public enum OccurrenceMatcher {
    /// How far from now an unmatched answer may reach.
    public static let window: TimeInterval = 45 * 60

    @MainActor
    public static func match(
        occurrenceID: UUID?,
        habitID: UUID?,
        in context: ModelContext,
        now: Date
    ) -> HabitOccurrence? {
        if let occurrenceID {
            let descriptor = FetchDescriptor<HabitOccurrence>(
                predicate: #Predicate { $0.id == occurrenceID }
            )
            if let exact = try? context.fetch(descriptor).first { return exact }
        }

        guard let habitID else { return nil }
        let all = (try? context.fetch(FetchDescriptor<HabitOccurrence>())) ?? []
        return all
            .filter {
                $0.habit?.id == habitID
                    && $0.status == .pending
                    && abs($0.scheduledAt.timeIntervalSince(now)) < window
            }
            .min {
                abs($0.scheduledAt.timeIntervalSince(now))
                    < abs($1.scheduledAt.timeIntervalSince(now))
            }
    }
}
