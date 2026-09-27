import Foundation

nonisolated public struct PlannedNudge: Hashable, Sendable {
    public let habitID: UUID
    public let fireAt: Date
    /// The moment the habit's own schedule asked for, before any collision
    /// handling. Kept so the queue can be explained and tested.
    public let wantedAt: Date
    /// Nudges that wanted the same moment share a group.
    public let group: UUID?
    /// 0 is the one that fires on time; 1 and up follow it.
    public let queuePosition: Int

    public init(
        habitID: UUID,
        fireAt: Date,
        wantedAt: Date? = nil,
        group: UUID? = nil,
        queuePosition: Int = 0
    ) {
        self.habitID = habitID
        self.fireAt = fireAt
        self.wantedAt = wantedAt ?? fireAt
        self.group = group
        self.queuePosition = queuePosition
    }
}

nonisolated public struct HabitPlanInput: Sendable, Identifiable {
    public let id: UUID
    public let schedule: Schedule
    public let intensity: Intensity
    public let isPaused: Bool

    public init(id: UUID, schedule: Schedule, intensity: Intensity, isPaused: Bool) {
        self.id = id
        self.schedule = schedule
        self.intensity = intensity
        self.isPaused = isPaused
    }
}

/// What the app should actually register with each iOS subsystem.
///
/// The three buckets exist because the three tiers draw on three *separate*
/// system budgets. Lumping them together is how reminders silently vanish.
nonisolated public struct NudgePlan: Sendable, Equatable {
    public var notifications: [PlannedNudge]
    public var liveActivities: [PlannedNudge]
    public var alarms: [PlannedNudge]

    /// Every planned nudge regardless of tier, oldest first.
    public var all: [PlannedNudge] {
        (notifications + liveActivities + alarms).sorted { $0.fireAt < $1.fireAt }
    }

    public init(notifications: [PlannedNudge] = [], liveActivities: [PlannedNudge] = [], alarms: [PlannedNudge] = []) {
        self.notifications = notifications
        self.liveActivities = liveActivities
        self.alarms = alarms
    }
}

nonisolated public enum SchedulingService {
    /// Apple caps pending local notification requests at 64 per app. This is a
    /// system limit with no workaround, confirmed by Apple DTS:
    /// https://developer.apple.com/forums/thread/811171
    public static let pendingNotificationLimit = 64

    /// ActivityKit's concurrent-activity limit is deliberately undocumented by
    /// Apple. The widely-quoted "5" is not Apple-sourced, so we stay well under
    /// any plausible value and spill the rest into notifications.
    public static let liveActivityBudget = 3

    /// The soonest nudge across every habit, ignoring every budget. Used to
    /// tell the user when the next one actually lands, so "nothing due today"
    /// never reads as "the app is broken".
    public static func nextFireTime(
        habits: [HabitPlanInput],
        from now: Date,
        withinDays days: Int = 8,
        calendar: Calendar = .current
    ) -> (habitID: UUID, date: Date)? {
        habits
            .filter { !$0.isPaused }
            .compactMap { habit -> (UUID, Date)? in
                guard let first = fireTimes(
                    for: habit.schedule, from: now,
                    horizon: TimeInterval(days) * 24 * 3600, calendar: calendar
                ).first else { return nil }
                return (habit.id, first)
            }
            .min { $0.1 < $1.1 }
            .map { (habitID: $0.0, date: $0.1) }
    }

    /// How far ahead we materialize nudges. Long enough to survive a couple of
    /// days without opening the app, short enough that the 64 slots stay dense.
    public static let horizon: TimeInterval = 48 * 3600

    public static func plan(
        habits: [HabitPlanInput],
        from now: Date,
        horizon: TimeInterval = horizon,
        calendar: Calendar = .current
    ) -> NudgePlan {
        let active = habits.filter { !$0.isPaused }
        guard !active.isEmpty else { return NudgePlan() }

        var candidates: [UUID: [Date]] = [:]
        for habit in active {
            candidates[habit.id] = fireTimes(
                for: habit.schedule, from: now, horizon: horizon, calendar: calendar
            )
        }

        var plan = NudgePlan()

        // Alarm tier: AlarmKit keeps its own recurring schedule, so we only
        // hand it the distinct clock times rather than every future instance.
        let alarmHabits = active.filter { $0.intensity == .alarm }
        for habit in alarmHabits {
            for date in (candidates[habit.id] ?? []) {
                plan.alarms.append(PlannedNudge(habitID: habit.id, fireAt: date))
            }
        }

        // Standard tier: a few become scheduled Live Activities, the rest
        // degrade to plain notifications.
        //
        // Allocated fairly rather than soonest-first. A habit firing every six
        // minutes would otherwise take all three slots inside a quarter of an
        // hour and every other habit would silently lose its Lock Screen card.
        let standardHabits = active.filter { $0.intensity == .standard }
        var standardByHabit: [UUID: [PlannedNudge]] = [:]
        for habit in standardHabits {
            standardByHabit[habit.id] = (candidates[habit.id] ?? []).map {
                PlannedNudge(habitID: habit.id, fireAt: $0)
            }
        }
        plan.liveActivities = allocate(standardByHabit, limit: liveActivityBudget)
        let chosen = Set(plan.liveActivities)
        let standardOverflow = standardByHabit.values.flatMap { $0 }
            .filter { !chosen.contains($0) }
            .sorted { $0.fireAt < $1.fireAt }

        // Gentle tier plus the standard overflow share the 64 notification slots.
        let gentleHabits = active.filter { $0.intensity == .gentle }
        var byHabit: [UUID: [PlannedNudge]] = [:]
        for habit in gentleHabits {
            byHabit[habit.id] = (candidates[habit.id] ?? []).map {
                PlannedNudge(habitID: habit.id, fireAt: $0)
            }
        }
        for nudge in standardOverflow {
            byHabit[nudge.habitID, default: []].append(nudge)
        }
        plan.notifications = allocate(byHabit, limit: pendingNotificationLimit)

        // Collisions are resolved across every tier at once. An alarm and a
        // Lock Screen card landing on the same minute is the same problem as
        // two banners, and splitting the logic per tier let that through.
        plan = queued(plan)

        return plan
    }

    /// Nudges landing closer together than this are treated as a collision.
    public static let collisionWindow: TimeInterval = 60
    /// How far apart queued nudges are placed. Close enough to read as "one
    /// after another", far enough that they are two distinct interruptions.
    public static let queueGapSeconds: TimeInterval = 45

    /// Turns simultaneous nudges into an ordered queue.
    ///
    /// The first keeps the time its habit asked for. The rest are pushed to
    /// follow it, and carry the group and position that let the app pull the
    /// next one forward the moment its predecessor is answered.
    ///
    /// Everything is still pre-scheduled with the operating system, so nothing
    /// depends on the app being alive: if you never answer the first, the
    /// second still fires on its own. The queue only ever makes a nudge
    /// arrive sooner, never later than its staggered slot, and never drops one.
    static func queued(_ plan: NudgePlan) -> NudgePlan {
        struct Slot { let bucket: Int; let nudge: PlannedNudge }

        var slots: [Slot] =
            plan.notifications.map { Slot(bucket: 0, nudge: $0) }
            + plan.liveActivities.map { Slot(bucket: 1, nudge: $0) }
            + plan.alarms.map { Slot(bucket: 2, nudge: $0) }
        slots.sort { $0.nudge.wantedAt < $1.nudge.wantedAt }

        var result = NudgePlan()
        var anchor: Date?
        var group: UUID?
        var position = 0
        var lastPlaced: Date?
        var lastHabit: UUID?

        for slot in slots {
            let wanted = slot.nudge.wantedAt
            let collides = anchor.map { wanted.timeIntervalSince($0) < collisionWindow } ?? false
            // A habit's own cadence is its `minIntervalMinutes` decision, so
            // back-to-back nudges from one habit are never treated as a clash.
            let sameHabit = lastHabit == slot.nudge.habitID

            let fireAt: Date
            if collides && !sameHabit, let previous = lastPlaced {
                position += 1
                fireAt = previous.addingTimeInterval(queueGapSeconds)
            } else {
                anchor = wanted
                group = UUID()
                position = 0
                fireAt = wanted
            }

            let placed = PlannedNudge(
                habitID: slot.nudge.habitID,
                fireAt: fireAt,
                wantedAt: wanted,
                group: position == 0 && !collides ? group : group,
                queuePosition: position
            )
            switch slot.bucket {
            case 0: result.notifications.append(placed)
            case 1: result.liveActivities.append(placed)
            default: result.alarms.append(placed)
            }
            lastPlaced = fireAt
            lastHabit = slot.nudge.habitID
        }
        return result
    }

    /// Fair-share allocation.
    ///
    /// Taking the globally-earliest 64 would let one every-15-minutes habit eat
    /// every slot and starve a once-a-day habit that matters more. So each
    /// habit is guaranteed an equal floor first, then leftover slots are filled
    /// earliest-first so the budget is never wasted.
    static func allocate(_ byHabit: [UUID: [PlannedNudge]], limit: Int) -> [PlannedNudge] {
        let nonEmpty = byHabit.filter { !$0.value.isEmpty }
        guard !nonEmpty.isEmpty, limit > 0 else { return [] }

        let share = max(1, limit / nonEmpty.count)
        var taken: [PlannedNudge] = []
        var leftovers: [PlannedNudge] = []

        for (_, nudges) in nonEmpty {
            let sorted = nudges.sorted { $0.fireAt < $1.fireAt }
            taken.append(contentsOf: sorted.prefix(share))
            leftovers.append(contentsOf: sorted.dropFirst(share))
        }

        taken.sort { $0.fireAt < $1.fireAt }
        if taken.count > limit { taken = Array(taken.prefix(limit)) }

        if taken.count < limit {
            leftovers.sort { $0.fireAt < $1.fireAt }
            taken.append(contentsOf: leftovers.prefix(limit - taken.count))
            taken.sort { $0.fireAt < $1.fireAt }
        }
        return taken
    }

    // MARK: - Reconciliation

    /// One future occurrence as the reconciler sees it.
    public struct ExistingNudge: Hashable, Sendable {
        public let id: UUID
        public let habitID: UUID
        public let scheduledAt: Date
        public let isPending: Bool
        public let isPinned: Bool

        public init(id: UUID, habitID: UUID, scheduledAt: Date, isPending: Bool, isPinned: Bool) {
            self.id = id
            self.habitID = habitID
            self.scheduledAt = scheduledAt
            self.isPending = isPending
            self.isPinned = isPinned
        }
    }

    /// Which stored occurrences the new plan has orphaned.
    ///
    /// Editing a habit's schedule used to leave the old schedule's rows on the
    /// Home screen, which reads as "my edit did nothing". Three things are
    /// deliberately never purged: anything already answered (that is history),
    /// anything in the past (same), and anything pinned by hand.
    public static func stale(
        existing: [ExistingNudge],
        plan: NudgePlan,
        now: Date
    ) -> [UUID] {
        var live: Set<Slot> = []
        for nudge in plan.notifications + plan.liveActivities + plan.alarms {
            live.insert(Slot(habitID: nudge.habitID, minute: minuteStamp(nudge.fireAt)))
        }
        for nudge in existing where nudge.isPinned {
            live.insert(Slot(habitID: nudge.habitID, minute: minuteStamp(nudge.scheduledAt)))
        }

        return existing
            .filter { $0.isPending && $0.scheduledAt > now && !$0.isPinned }
            .filter { !live.contains(Slot(habitID: $0.habitID, minute: minuteStamp($0.scheduledAt))) }
            .map(\.id)
    }

    struct Slot: Hashable {
        let habitID: UUID
        let minute: Int
    }

    /// Whole-minute bucket, so a sub-second difference is not a new nudge.
    static func minuteStamp(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    // MARK: - Fire time generation

    public static func fireTimes(
        for schedule: Schedule,
        from now: Date,
        horizon: TimeInterval,
        calendar: Calendar = .current
    ) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var result: [Date] = []
        var day = calendar.startOfDay(for: now)

        while day < end {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1) }

            let weekday = calendar.component(.weekday, from: day)
            guard schedule.weekdays.contains(weekday) else { continue }

            let minutes = minuteOffsets(for: schedule, calendar: calendar, day: day)
            var lastKept: Int?
            for minute in minutes {
                if let last = lastKept, minute - last < schedule.minIntervalMinutes { continue }
                guard let fire = calendar.date(byAdding: .minute, value: minute, to: day) else { continue }
                if fire > now && fire <= end { result.append(fire) }
                lastKept = minute
            }
        }
        return result.sorted()
    }

    /// Minutes from midnight for a single day, before the horizon filter.
    static func minuteOffsets(for schedule: Schedule, calendar: Calendar, day: Date) -> [Int] {
        let start = schedule.windowStartMinute
        let end = schedule.windowEndMinute
        guard end > start else { return [] }

        switch schedule.kind {
        case .interval(let minutes):
            let step = max(minutes, schedule.minIntervalMinutes, 1)
            return Array(stride(from: start, through: end, by: step))

        case .fixedTimes(let times):
            return times.sorted()

        case .spread(let count, let period):
            let perDay = dailyCount(count: count, period: period, schedule: schedule)
            guard perDay > 0 else { return [] }
            if perDay == 1 { return [(start + end) / 2] }
            let step = (end - start) / (perDay - 1)
            return (0..<perDay).map { start + $0 * step }
        }
    }

    /// Converts a per-week or per-month target into a per-day count, given how
    /// many days of the week the habit is actually allowed to fire on.
    static func dailyCount(count: Int, period: Period, schedule: Schedule) -> Int {
        let activeDays = max(schedule.weekdays.count, 1)
        switch period {
        case .day:
            return count
        case .week:
            return Int(ceil(Double(count) / Double(activeDays)))
        case .month:
            let perWeek = Double(count) / 4.345
            return Int(ceil(perWeek / Double(activeDays)))
        }
    }
}
