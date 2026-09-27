import Foundation
import UserNotifications

nonisolated struct WeeklyReview: Sendable {
    struct HabitLine: Sendable, Identifiable {
        var id: UUID
        var name: String
        var symbol: String
        var tintHex: String
        var completed: Int
        var answered: Int
        var streak: Int
        var rate: Double
        var suggestion: String?
    }

    var completed: Int
    var answered: Int
    var rate: Double
    /// Change in completion rate against the previous seven days.
    var delta: Double
    var bestDay: (date: Date, completed: Int)?
    var lines: [HabitLine]

    var strongest: HabitLine? { lines.filter { $0.answered > 0 }.max { $0.rate < $1.rate } }
    var weakest: HabitLine? { lines.filter { $0.answered > 0 }.min { $0.rate < $1.rate } }
}

nonisolated enum WeeklyReviewService {
    static let notificationID = "psst.review.weekly"
    static let categoryID = "PSST_REVIEW"

    @MainActor
    static func build(habits: [Habit], now: Date = .now, calendar: Calendar = .current) -> WeeklyReview {
        let all = habits.flatMap(\.occurrences)
        let week = HabitStatsService.stats(for: all, days: 7, now: now, calendar: calendar)

        // Previous seven days, so the headline number has a direction.
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let previous = HabitStatsService.stats(for: all, days: 7, now: previousEnd, calendar: calendar)

        let days = HabitStatsService.daily(for: all, days: 7, now: now, calendar: calendar)
        let best = days.max { $0.completed < $1.completed }

        let lines = habits.map { habit -> WeeklyReview.HabitLine in
            let stats = HabitStatsService.stats(for: habit.occurrences, days: 7, now: now, calendar: calendar)
            return WeeklyReview.HabitLine(
                id: habit.id,
                name: habit.name,
                symbol: habit.symbol,
                tintHex: habit.tintHex,
                completed: stats.completed,
                answered: stats.total,
                streak: HabitStatsService.streak(for: habit.occurrences, now: now, calendar: calendar),
                rate: stats.completionRate,
                suggestion: ScheduleAdvisor.suggestion(
                    schedule: habit.schedule,
                    intensity: habit.intensity,
                    occurrences: habit.occurrences,
                    calendar: calendar
                )?.rationale
            )
        }
        .sorted { $0.rate > $1.rate }

        return WeeklyReview(
            completed: week.completed,
            answered: week.total,
            rate: week.completionRate,
            delta: week.completionRate - previous.completionRate,
            bestDay: (best?.completed ?? 0) > 0 ? (best!.date, best!.completed) : nil,
            lines: lines
        )
    }

    /// One repeating request, so it costs a single slot of the 64 forever.
    static func schedule(
        weekday: Int = 1,
        hour: Int = 18,
        on center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Your week"
        content.body = "Here is what actually stuck."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.interruptionLevel = .active

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }
}
