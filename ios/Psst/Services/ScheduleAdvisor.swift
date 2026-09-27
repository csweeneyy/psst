import Foundation

/// A concrete, applyable change derived from how the habit is actually going.
nonisolated struct ScheduleSuggestion: Sendable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// Shift the active window away from hours that never get answered.
        case narrowWindow(startMinute: Int, endMinute: Int)
        /// Move explicit clock times to an hour that does get answered.
        case moveTimes([Int])
        /// Fire less often, because the current rate is being ignored.
        case slowDown(minutes: Int)
        /// Escalate the tier, because it is being seen and dismissed.
        case raiseIntensity(Intensity)
    }

    var id = UUID()
    var kind: Kind
    /// One line, citing the number it was derived from.
    var rationale: String
    var actionTitle: String

    func applied(to schedule: Schedule) -> Schedule {
        var updated = schedule
        switch kind {
        case .narrowWindow(let start, let end):
            updated.windowStartMinute = start
            updated.windowEndMinute = end
        case .moveTimes(let times):
            updated.kind = .fixedTimes(times)
        case .slowDown(let minutes):
            if case .interval = schedule.kind {
                updated.kind = .interval(minutes: minutes)
                updated.minIntervalMinutes = max(schedule.minIntervalMinutes, minutes / 2)
            }
        case .raiseIntensity:
            break
        }
        return updated
    }
}

/// Turns the response heatmap into one suggestion, or none.
///
/// Deliberately conservative. A suggestion the user rejects twice is worse
/// than no suggestion, so every rule below demands real evidence before it
/// fires, and only the strongest single candidate is ever returned.
nonisolated enum ScheduleAdvisor {

    /// Below this, an hour counts as "being ignored".
    static let poorRate = 0.4
    /// Above this, an hour counts as reliable.
    static let goodRate = 0.7
    /// Fewer answered nudges than this in an hour is noise, not a pattern.
    static let minimumSamples = 3
    /// Nothing is suggested until the habit has this many answered nudges.
    static let minimumTotal = 8

    static func suggestion(
        schedule: Schedule,
        intensity: Intensity,
        occurrences: [HabitOccurrence],
        calendar: Calendar = .current
    ) -> ScheduleSuggestion? {
        let hours = HabitStatsService.hourly(for: occurrences, calendar: calendar)
        let answered = hours.reduce(0) { $0 + $1.answered }
        guard answered >= minimumTotal else { return nil }

        let credible = hours.filter { $0.answered >= minimumSamples }
        guard !credible.isEmpty else { return nil }

        let overall = Double(hours.reduce(0) { $0 + $1.completed }) / Double(answered)
        let best = credible.max { $0.rate < $1.rate }
        let worst = credible.min { $0.rate < $1.rate }

        switch schedule.kind {
        case .fixedTimes(let times):
            // One clock time, reliably ignored, and a demonstrably better hour
            // exists. Move it.
            guard let worst, let best,
                  worst.rate < poorRate, best.rate >= goodRate,
                  best.hour != worst.hour,
                  times.contains(where: { $0 / 60 == worst.hour })
            else { return nil }

            let moved = times.map { $0 / 60 == worst.hour ? best.hour * 60 + ($0 % 60) : $0 }
            return ScheduleSuggestion(
                kind: .moveTimes(moved),
                rationale: "You answer \(percent(best.rate)) of these at \(hourLabel(best.hour)) but only \(percent(worst.rate)) at \(hourLabel(worst.hour)).",
                actionTitle: "Move to \(hourLabel(best.hour))"
            )

        case .interval, .spread:
            // Dead hours at the edges of the window: pull the window in.
            if let tightened = tightenedWindow(schedule: schedule, hours: credible) {
                return ScheduleSuggestion(
                    kind: .narrowWindow(startMinute: tightened.start, endMinute: tightened.end),
                    rationale: tightened.reason,
                    actionTitle: "Use \(Schedule.clock(tightened.start)) to \(Schedule.clock(tightened.end))"
                )
            }

            // Being ignored across the board. Two readings, and which one is
            // right depends on whether the tier can still escalate.
            guard overall < poorRate else { return nil }
            if case .interval(let minutes) = schedule.kind, minutes < 180 {
                let slower = min(minutes * 2, 6 * 60)
                return ScheduleSuggestion(
                    kind: .slowDown(minutes: slower),
                    rationale: "Only \(percent(overall)) of these get answered. Fewer, louder nudges tend to beat more of them.",
                    actionTitle: "Every \(Schedule.duration(slower))"
                )
            }
            if intensity != .alarm {
                let next: Intensity = intensity == .gentle ? .standard : .alarm
                return ScheduleSuggestion(
                    kind: .raiseIntensity(next),
                    rationale: "\(percent(overall)) answered. \(next.title) is harder to scroll past.",
                    actionTitle: "Make it \(next.title)"
                )
            }
            return nil
        }
    }

    /// Trims hours at either end of the window that are reliably ignored.
    private static func tightenedWindow(
        schedule: Schedule,
        hours: [HourSlice]
    ) -> (start: Int, end: Int, reason: String)? {
        let startHour = schedule.windowStartMinute / 60
        let endHour = schedule.windowEndMinute / 60
        guard endHour - startHour >= 4 else { return nil }

        let byHour = Dictionary(uniqueKeysWithValues: hours.map { ($0.hour, $0) })
        var start = startHour
        var end = endHour
        var trimmed: [Int] = []

        while start < end - 3, let slice = byHour[start], slice.rate < poorRate {
            trimmed.append(start)
            start += 1
        }
        while end > start + 3, let slice = byHour[end - 1], slice.rate < poorRate {
            trimmed.append(end - 1)
            end -= 1
        }
        guard !trimmed.isEmpty else { return nil }

        // Only worth suggesting if something that actually works survives the
        // trim. If every hour in the window is ignored, narrowing it is
        // rearranging deck chairs; the honest advice is to change the cadence
        // or the tier instead.
        let survivors = hours.filter { $0.hour >= start && $0.hour < end }
        guard survivors.contains(where: { $0.rate >= goodRate }) else { return nil }

        let label = trimmed.sorted().map(hourLabel).joined(separator: " and ")
        return (
            start * 60,
            end * 60,
            "You almost never answer these around \(label). Skipping that window keeps the rest useful."
        )
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private static func hourLabel(_ hour: Int) -> String {
        Schedule.clock(hour * 60)
    }
}
