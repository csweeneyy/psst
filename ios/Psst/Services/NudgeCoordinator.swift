import Foundation
import SwiftData
import UserNotifications

/// Owns the lifecycle of everything that touches an iOS notification budget.
///
/// Per the project's Safeloop convention the entrypoint owns resources, so the
/// app holds exactly one of these and the services stay stateless.
@Observable
final class NudgeCoordinator {
    private(set) var lastSync: Date?
    private(set) var scheduledNotifications = 0
    private(set) var scheduledLiveActivities = 0
    private(set) var scheduledAlarms = 0
    private(set) var lastError: String?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        NotificationService.registerCategories(on: center)
    }

    func requestPermissions() async {
        _ = await NotificationService.requestAuthorization(on: center)
        // Repeating, so scheduling it once per launch is idempotent.
        await WeeklyReviewService.schedule(on: center)
    }

    /// Rebuilds the entire forward schedule from the current habit set.
    ///
    /// Called on launch, on foreground, after any habit edit, and after every
    /// notification response. Cheap enough to run eagerly; the alternative is
    /// a stale 64-slot budget, which loses reminders silently.
    func resync(context: ModelContext, now: Date = .now) async {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })

        var plan = SchedulingService.plan(
            habits: habits.map {
                HabitPlanInput(id: $0.id, schedule: $0.schedule, intensity: $0.intensity, isPaused: $0.isPaused)
            },
            from: now
        )

        // A nudge you moved by hand is part of the schedule, not noise. Fold
        // pinned occurrences into the plan so they still get a notification.
        let pinned = pinnedPending(context: context, now: now)
        for occurrence in pinned where !occurrence.isFollowUp {
            guard let habitID = occurrence.habit?.id, let habit = byID[habitID], !habit.isPaused else { continue }
            let nudge = PlannedNudge(habitID: habitID, fireAt: occurrence.scheduledAt)
            switch habit.intensity {
            case .standard: plan.liveActivities.append(nudge)
            case .alarm, .gentle: plan.notifications.append(nudge)
            }
        }
        plan.notifications.sort { $0.fireAt < $1.fireAt }
        plan.liveActivities.sort { $0.fireAt < $1.fireAt }

        await LiveActivityService.dropOrphans(livingHabitIDs: Set(byID.keys))

        let occurrenceIDs = materialize(plan, habits: byID, context: context, now: now, pinned: pinned)

        var notificationNudges = plan.notifications

        switch await LiveActivityService.sync(plan.liveActivities, habits: byID, occurrenceIDs: occurrenceIDs) {
        case .success(let started):
            scheduledLiveActivities = started.count
            // Anything ActivityKit refused still has to reach the user.
            let refused = plan.liveActivities.filter { !started.contains($0) }
            notificationNudges.append(contentsOf: refused)
            notificationNudges.sort { $0.fireAt < $1.fireAt }
        case .failure:
            scheduledLiveActivities = 0
            notificationNudges.append(contentsOf: plan.liveActivities)
            notificationNudges.sort { $0.fireAt < $1.fireAt }
        }

        switch await NotificationService.sync(
            notificationNudges, habits: byID, occurrenceIDs: occurrenceIDs, on: center
        ) {
        case .success(let count): scheduledNotifications = count
        case .failure(let error): lastError = error.localizedDescription
        }

        if habits.contains(where: { $0.intensity == .alarm && !$0.isPaused }) {
            switch await AlarmService.sync(habits, plan: plan) {
            case .success(let count): scheduledAlarms = count
            case .failure(.notAuthorized): scheduledAlarms = 0
            case .failure(.limitReached): lastError = "Hit the alarm limit. Move a habit down to Standard."
            case .failure(.underlying(let error)): lastError = error.localizedDescription
            }
        } else {
            AlarmService.cancelAll()
            scheduledAlarms = 0
        }

        WidgetSnapshot.reload()
        lastSync = now
        psstLog.notice(
            "resync: \(self.scheduledNotifications) notifications, \(self.scheduledLiveActivities) activities, \(self.scheduledAlarms) alarms"
        )
    }

    /// Creates the `HabitOccurrence` rows the Today screen and the intents read.
    /// Reuses an existing row for the same habit and minute so a resync does not
    /// wipe an answer the user already gave.
    private func pinnedPending(context: ModelContext, now: Date) -> [HabitOccurrence] {
        let all = (try? context.fetch(FetchDescriptor<HabitOccurrence>())) ?? []
        return all.filter { $0.isPinned && $0.status == .pending && $0.scheduledAt > now }
    }

    private func materialize(
        _ plan: NudgePlan,
        habits: [UUID: Habit],
        context: ModelContext,
        now: Date,
        pinned: [HabitOccurrence]
    ) -> [PlannedNudge: UUID] {
        _ = pinned
        let all = plan.notifications + plan.liveActivities + plan.alarms
        let existing = (try? context.fetch(FetchDescriptor<HabitOccurrence>())) ?? []

        var index: [String: HabitOccurrence] = [:]
        for occurrence in existing {
            guard let habitID = occurrence.habit?.id else { continue }
            index[key(habitID, occurrence.scheduledAt)] = occurrence
        }

        var result: [PlannedNudge: UUID] = [:]
        for nudge in all {
            let k = key(nudge.habitID, nudge.fireAt)
            if let found = index[k] {
                // Group membership can change between syncs as habits move.
                found.queueGroup = nudge.group
                found.queuePosition = nudge.queuePosition
                result[nudge] = found.id
                continue
            }
            guard let habit = habits[nudge.habitID] else { continue }
            let occurrence = HabitOccurrence(scheduledAt: nudge.fireAt, habit: habit)
            occurrence.queueGroup = nudge.group
            occurrence.queuePosition = nudge.queuePosition
            context.insert(occurrence)
            index[k] = occurrence
            result[nudge] = occurrence.id
        }

        // Drop future pending occurrences the new plan no longer contains.
        // Without this, editing a habit's schedule leaves the old schedule's
        // rows sitting on the Home screen forever, which reads as "my edit
        // did nothing". The decision itself lives in `SchedulingService.stale`
        // so it can be tested without SwiftData.
        let orphaned = Set(SchedulingService.stale(
            existing: existing.compactMap { occurrence in
                guard let habitID = occurrence.habit?.id else { return nil }
                return SchedulingService.ExistingNudge(
                    id: occurrence.id,
                    habitID: habitID,
                    scheduledAt: occurrence.scheduledAt,
                    isPending: occurrence.status == .pending,
                    isPinned: occurrence.isPinned
                )
            },
            plan: plan,
            now: now
        ))
        for occurrence in existing where orphaned.contains(occurrence.id) {
            context.delete(occurrence)
        }

        // Anything still pending whose moment has passed is a miss, not a
        // pending item. Without this the Home list grows forever.
        for occurrence in existing where occurrence.status == .pending && occurrence.scheduledAt < now.addingTimeInterval(-3600) {
            occurrence.status = .missed
        }

        try? context.save()
        return result
    }

    private func key(_ habit: UUID, _ date: Date) -> String {
        "\(habit.uuidString)-\(Int(date.timeIntervalSince1970 / 60))"
    }
}
