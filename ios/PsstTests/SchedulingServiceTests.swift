import Foundation
import Testing
@testable import Psst

private var utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("Scheduling engine")
struct SchedulingServiceTests {

    @Test("Never exceeds the 64 pending notification limit, even under heavy load")
    func respectsSystemLimit() {
        // 20 habits nagging every 15 minutes for 16 hours a day would want
        // roughly 1,280 requests across the horizon. iOS accepts 64.
        let habits = (0..<20).map { _ in
            HabitPlanInput(
                id: UUID(),
                schedule: Schedule(
                    kind: .interval(minutes: 15),
                    windowStartMinute: 6 * 60,
                    windowEndMinute: 22 * 60,
                    minIntervalMinutes: 15
                ),
                intensity: .gentle,
                isPaused: false
            )
        }
        let plan = SchedulingService.plan(habits: habits, from: at(2026, 3, 2, 5), calendar: utc)
        #expect(plan.notifications.count <= SchedulingService.pendingNotificationLimit)
        #expect(plan.notifications.count == SchedulingService.pendingNotificationLimit)
    }

    @Test("A chatty habit cannot starve a once-a-day habit")
    func fairShare() {
        let chatty = UUID()
        let quiet = UUID()
        let habits = [
            HabitPlanInput(
                id: chatty,
                schedule: Schedule(kind: .interval(minutes: 15), windowStartMinute: 0, windowEndMinute: 23 * 60, minIntervalMinutes: 15),
                intensity: .gentle, isPaused: false),
            HabitPlanInput(
                id: quiet,
                schedule: Schedule(kind: .fixedTimes([20 * 60]), minIntervalMinutes: 60),
                intensity: .gentle, isPaused: false),
        ]
        let plan = SchedulingService.plan(habits: habits, from: at(2026, 3, 2, 5), calendar: utc)
        // Globally-earliest-first would have handed all 64 slots to `chatty`
        // before reaching 8 PM. Fair share guarantees the quiet habit survives.
        #expect(plan.notifications.contains { $0.habitID == quiet })
    }

    @Test("minIntervalMinutes is a hard floor the schedule cannot undercut")
    func minimumIntervalIsEnforced() {
        // Asking for every minute while declaring a 120 minute floor.
        let schedule = Schedule(
            kind: .interval(minutes: 1),
            windowStartMinute: 9 * 60,
            windowEndMinute: 17 * 60,
            minIntervalMinutes: 120
        )
        let times = SchedulingService.fireTimes(
            for: schedule, from: at(2026, 3, 2, 0), horizon: 24 * 3600, calendar: utc
        )
        #expect(times.count == 5) // 9, 11, 13, 15, 17
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= 120 * 60)
        }
    }

    @Test("Nothing fires outside the active window or on excluded weekdays")
    func respectsWindowAndWeekdays() {
        // 2026-03-02 is a Monday, so weekday 2. Allow Monday only.
        let schedule = Schedule(
            kind: .interval(minutes: 60),
            windowStartMinute: 9 * 60,
            windowEndMinute: 11 * 60,
            weekdays: [2],
            minIntervalMinutes: 30
        )
        let times = SchedulingService.fireTimes(
            for: schedule, from: at(2026, 3, 2, 0), horizon: 72 * 3600, calendar: utc
        )
        #expect(times.count == 3) // 9, 10, 11 on Monday only
        for t in times {
            #expect(utc.component(.weekday, from: t) == 2)
            let minute = utc.component(.hour, from: t) * 60 + utc.component(.minute, from: t)
            #expect(minute >= 9 * 60 && minute <= 11 * 60)
        }
    }

    @Test("Standard tier spills past the Live Activity budget into notifications")
    func liveActivityOverflowDegrades() {
        let habits = (0..<4).map { _ in
            HabitPlanInput(
                id: UUID(),
                schedule: Schedule(kind: .interval(minutes: 120), minIntervalMinutes: 120),
                intensity: .standard,
                isPaused: false
            )
        }
        let plan = SchedulingService.plan(habits: habits, from: at(2026, 3, 2, 8), calendar: utc)
        #expect(plan.liveActivities.count == SchedulingService.liveActivityBudget)
        // The reminders beyond the budget must still reach the user somehow.
        #expect(!plan.notifications.isEmpty)
    }

    @Test("A chatty habit cannot take every Live Activity slot")
    func liveActivityBudgetIsSharedFairly() {
        // Observed on device: a habit firing every 6 minutes inside a half hour
        // window consumed all three Lock Screen slots and every other habit
        // silently lost its card.
        let chatty = UUID()
        let quiet = UUID()
        let habits = [
            HabitPlanInput(
                id: chatty,
                schedule: Schedule(
                    kind: .interval(minutes: 6),
                    windowStartMinute: 17 * 60 + 30,
                    windowEndMinute: 18 * 60,
                    minIntervalMinutes: 6
                ),
                intensity: .standard, isPaused: false),
            HabitPlanInput(
                id: quiet,
                schedule: Schedule(kind: .fixedTimes([20 * 60]), minIntervalMinutes: 60),
                intensity: .standard, isPaused: false),
        ]
        let plan = SchedulingService.plan(habits: habits, from: at(2026, 3, 2, 8), calendar: utc)
        #expect(plan.liveActivities.count == SchedulingService.liveActivityBudget)
        #expect(plan.liveActivities.contains { $0.habitID == quiet })
    }

    @Test("The next fire time is reported even when it is days away")
    func nextFireTimeLooksPastTheHorizon() {
        // Monday-only habit, configured on a Saturday.
        let habits = [
            HabitPlanInput(
                id: UUID(),
                schedule: Schedule(kind: .fixedTimes([18 * 60]), weekdays: [2], minIntervalMinutes: 60),
                intensity: .standard, isPaused: false)
        ]
        let saturday = at(2026, 2, 28, 9)
        #expect(utc.component(.weekday, from: saturday) == 7)
        let next = SchedulingService.nextFireTime(habits: habits, from: saturday, calendar: utc)
        #expect(next != nil)
        if let next { #expect(utc.component(.weekday, from: next.date) == 2) }
    }

    @Test("A fixed time outside the active window still fires")
    func fixedTimesIgnoreTheWindow() {
        // An 8:30 AM alarm saved while the window still read 9 AM to 9 PM.
        // The times are the schedule; the window must not suppress them.
        let schedule = Schedule(
            kind: .fixedTimes([8 * 60 + 30]),
            windowStartMinute: 9 * 60,
            windowEndMinute: 21 * 60,
            minIntervalMinutes: 60
        )
        let times = SchedulingService.fireTimes(
            for: schedule, from: at(2026, 3, 2, 0), horizon: 24 * 3600, calendar: utc
        )
        #expect(times.count == 1)
        if let first = times.first {
            let minute = utc.component(.hour, from: first) * 60 + utc.component(.minute, from: first)
            #expect(minute == 8 * 60 + 30)
        }
    }

    @Test("Paused habits generate nothing at all")
    func pausedHabitsAreSilent() {
        let habits = [
            HabitPlanInput(id: UUID(), schedule: .everyTwoHours, intensity: .gentle, isPaused: true)
        ]
        let plan = SchedulingService.plan(habits: habits, from: at(2026, 3, 2, 8), calendar: utc)
        #expect(plan.notifications.isEmpty)
        #expect(plan.liveActivities.isEmpty)
        #expect(plan.alarms.isEmpty)
    }

    @Test("Weekly and monthly targets convert to a sane daily count")
    func periodConversion() {
        let everyDay = Schedule(kind: .spread(count: 3, period: .week), weekdays: [1,2,3,4,5,6,7])
        #expect(SchedulingService.dailyCount(count: 3, period: .week, schedule: everyDay) == 1)

        let weekdaysOnly = Schedule(kind: .spread(count: 10, period: .week), weekdays: [2,3,4,5,6])
        #expect(SchedulingService.dailyCount(count: 10, period: .week, schedule: weekdaysOnly) == 2)

        let monthly = Schedule(kind: .spread(count: 4, period: .month), weekdays: [1,2,3,4,5,6,7])
        #expect(SchedulingService.dailyCount(count: 4, period: .month, schedule: monthly) == 1)
    }
}
