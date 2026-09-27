import Foundation
import Testing
@testable import Psst

private var utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

@MainActor
private func occurrences(
    _ entries: [(hour: Int, completed: Bool, count: Int)]
) -> [HabitOccurrence] {
    let habit = Habit(name: "H", nudgeText: "n", intensity: .standard, schedule: .everyTwoHours)
    var result: [HabitOccurrence] = []
    var day = 0
    for entry in entries {
        for index in 0..<entry.count {
            day += 1
            let base = utc.date(from: DateComponents(year: 2026, month: 3, day: 1))!
            let date = utc.date(byAdding: .day, value: index, to: base)!
                .addingTimeInterval(TimeInterval(entry.hour * 3600))
            let occurrence = HabitOccurrence(scheduledAt: date, habit: habit)
            occurrence.status = entry.completed ? .completed : .missed
            result.append(occurrence)
        }
    }
    return result
}

@MainActor
@Suite("Schedule advisor")
struct ScheduleAdvisorTests {

    @Test("Says nothing without enough evidence")
    func staysQuietOnThinData() {
        let thin = occurrences([(hour: 15, completed: false, count: 2)])
        let suggestion = ScheduleAdvisor.suggestion(
            schedule: .everyTwoHours, intensity: .standard,
            occurrences: thin, calendar: utc
        )
        #expect(suggestion == nil)
    }

    @Test("Moves a fixed time from an ignored hour to a reliable one")
    func movesAFixedTime() {
        // 6 PM is ignored, 11 AM is answered.
        let data = occurrences([
            (hour: 18, completed: false, count: 6),
            (hour: 11, completed: true, count: 6),
        ])
        let schedule = Schedule(kind: .fixedTimes([18 * 60]), minIntervalMinutes: 60)
        let suggestion = ScheduleAdvisor.suggestion(
            schedule: schedule, intensity: .standard, occurrences: data, calendar: utc
        )
        guard case .moveTimes(let times)? = suggestion?.kind else {
            Issue.record("expected moveTimes, got \(String(describing: suggestion?.kind))")
            return
        }
        #expect(times == [11 * 60])
    }

    @Test("A suggestion is applied to the schedule it came from")
    func appliesCleanly() {
        let schedule = Schedule(kind: .fixedTimes([18 * 60]), minIntervalMinutes: 60)
        let suggestion = ScheduleSuggestion(
            kind: .moveTimes([11 * 60]), rationale: "", actionTitle: ""
        )
        guard case .fixedTimes(let times) = suggestion.applied(to: schedule).kind else {
            Issue.record("wrong kind"); return
        }
        #expect(times == [11 * 60])
    }

    @Test("A habit being ignored everywhere is slowed down, not tightened")
    func slowsDownWhenIgnoredEverywhere() {
        let data = occurrences([
            (hour: 10, completed: false, count: 5),
            (hour: 12, completed: false, count: 5),
            (hour: 14, completed: false, count: 5),
        ])
        let schedule = Schedule(
            kind: .interval(minutes: 60),
            windowStartMinute: 10 * 60, windowEndMinute: 15 * 60,
            minIntervalMinutes: 30
        )
        let suggestion = ScheduleAdvisor.suggestion(
            schedule: schedule, intensity: .standard, occurrences: data, calendar: utc
        )
        // Every hour in the window is poor, so there is no good edge to trim;
        // the honest advice is to fire less often.
        guard case .slowDown(let minutes)? = suggestion?.kind else {
            Issue.record("expected slowDown, got \(String(describing: suggestion?.kind))")
            return
        }
        #expect(minutes == 120)
    }

    @Test("A habit that is going well is left alone")
    func noSuggestionWhenHealthy() {
        let data = occurrences([
            (hour: 9, completed: true, count: 6),
            (hour: 13, completed: true, count: 6),
        ])
        let schedule = Schedule(
            kind: .interval(minutes: 120),
            windowStartMinute: 9 * 60, windowEndMinute: 14 * 60
        )
        #expect(ScheduleAdvisor.suggestion(
            schedule: schedule, intensity: .standard, occurrences: data, calendar: utc
        ) == nil)
    }
}
