import Foundation
import SwiftData
import WidgetKit

/// The minimum the widget and the Control Center control need to know.
///
/// A plain value type, because a `HabitOccurrence` cannot cross out of the
/// process that fetched it and the widget re-renders on its own schedule.
nonisolated public struct WidgetSnapshot: Sendable, Equatable {
    public var habitID: UUID?
    public var occurrenceID: UUID?
    public var habitName: String
    public var nudgeText: String
    public var symbol: String
    public var tintHex: String
    public var fireAt: Date?
    public var completedToday: Int
    public var scheduledToday: Int

    /// True once the moment has arrived and it is still unanswered.
    public var isDue: Bool {
        guard let fireAt else { return false }
        return fireAt <= .now
    }

    public static let empty = WidgetSnapshot(
        habitID: nil, occurrenceID: nil,
        habitName: "All clear", nudgeText: "Nothing due",
        symbol: "checkmark.circle", tintHex: HabitStyle.defaultTintHex,
        fireAt: nil, completedToday: 0, scheduledToday: 0
    )

    public static let placeholder = WidgetSnapshot(
        habitID: nil, occurrenceID: nil,
        habitName: "Posture check", nudgeText: "Psst... check your posture :)",
        symbol: "figure.stand", tintHex: HabitStyle.defaultTintHex,
        fireAt: .now.addingTimeInterval(1800), completedToday: 3, scheduledToday: 6
    )

    /// Soonest unanswered occurrence, plus today's tally.
    @MainActor
    public static func current(
        container: ModelContainer = PsstStore.shared,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<HabitOccurrence>())) ?? []
        let today = all.filter { calendar.isDateInToday($0.scheduledAt) && $0.habit != nil }

        let completed = today.filter { $0.status == .completed }.count
        let scheduled = today.count

        // Overdue first, then the soonest upcoming.
        let pending = all.filter { $0.status == .pending && $0.habit != nil }
        let next = pending
            .filter { $0.scheduledAt <= now }
            .max { $0.scheduledAt < $1.scheduledAt }
            ?? pending.filter { $0.scheduledAt > now }.min { $0.scheduledAt < $1.scheduledAt }

        guard let next, let habit = next.habit else {
            var snapshot = WidgetSnapshot.empty
            snapshot.completedToday = completed
            snapshot.scheduledToday = scheduled
            return snapshot
        }

        return WidgetSnapshot(
            habitID: habit.id,
            occurrenceID: next.id,
            habitName: habit.name,
            nudgeText: habit.nudgeText,
            symbol: habit.symbol,
            tintHex: habit.tintHex,
            fireAt: next.scheduledAt,
            completedToday: completed,
            scheduledToday: scheduled
        )
    }

    /// Call after anything that changes what is due.
    public static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
