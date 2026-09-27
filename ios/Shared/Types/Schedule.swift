import Foundation

nonisolated public enum Period: String, Codable, Sendable, CaseIterable, Identifiable {
    case day, week, month
    public var id: String { rawValue }
    public var noun: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }
}

nonisolated public enum ScheduleKind: Codable, Hashable, Sendable {
    /// Repeats every N minutes inside the active window. Posture checks.
    case interval(minutes: Int)
    /// Fires at specific clock times. Minutes from local midnight.
    case fixedTimes([Int])
    /// Spread `count` nudges evenly across the period's active window.
    case spread(count: Int, period: Period)

    // Hand-written so the wire format is a flat discriminated union the
    // Worker can emit directly. Swift's synthesized encoding for enums with
    // associated values produces `{"interval":{"minutes":120}}`, which is
    // awkward to generate from a language model tool schema.
    private enum CodingKeys: String, CodingKey {
        case type, minutes, times, count, period
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "interval":
            self = .interval(minutes: try c.decode(Int.self, forKey: .minutes))
        case "fixedTimes":
            self = .fixedTimes(try c.decode([Int].self, forKey: .times))
        case "spread":
            self = .spread(
                count: try c.decode(Int.self, forKey: .count),
                period: try c.decode(Period.self, forKey: .period)
            )
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown schedule kind \(other)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .interval(let minutes):
            try c.encode("interval", forKey: .type)
            try c.encode(minutes, forKey: .minutes)
        case .fixedTimes(let times):
            try c.encode("fixedTimes", forKey: .type)
            try c.encode(times, forKey: .times)
        case .spread(let count, let period):
            try c.encode("spread", forKey: .type)
            try c.encode(count, forKey: .count)
            try c.encode(period, forKey: .period)
        }
    }
}

nonisolated public struct Schedule: Codable, Hashable, Sendable {
    public var kind: ScheduleKind
    /// Minutes from local midnight. Nothing fires outside this window.
    public var windowStartMinute: Int
    public var windowEndMinute: Int
    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday:)`.
    public var weekdays: Set<Int>
    /// Hard floor. The assistant cannot schedule two nudges for this habit
    /// closer together than this, no matter what you ask it for. This is the
    /// rule that stops "every two hours" drifting into "every minute".
    public var minIntervalMinutes: Int

    public init(
        kind: ScheduleKind,
        windowStartMinute: Int = 9 * 60,
        windowEndMinute: Int = 21 * 60,
        weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7],
        minIntervalMinutes: Int = 30
    ) {
        self.kind = kind
        self.windowStartMinute = windowStartMinute
        self.windowEndMinute = windowEndMinute
        self.weekdays = weekdays
        self.minIntervalMinutes = minIntervalMinutes
    }

    public static let everyTwoHours = Schedule(kind: .interval(minutes: 120))

    public var summary: String {
        let window = "\(Self.clock(windowStartMinute)) to \(Self.clock(windowEndMinute))"
        let days = dayDescriptor.map { ", \($0)" } ?? ""
        switch kind {
        case .interval(let minutes):
            let every = minutes == 60 ? "Every hour" : "Every \(Self.duration(minutes))"
            return "\(every), \(window)\(days)"
        case .fixedTimes(let times):
            // No window here: explicit clock times are not constrained by one.
            return times.map(Self.clock).joined(separator: ", ") + days
        case .spread(let count, let period):
            return "\(count)x per \(period.noun), \(window)\(days)"
        }
    }

    /// `nil` when the habit runs every day, so the common case stays terse.
    public var dayDescriptor: String? {
        if weekdays.count == 7 { return nil }
        if weekdays == [2, 3, 4, 5, 6] { return "weekdays" }
        if weekdays == [1, 7] { return "weekends" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return weekdays.sorted().compactMap { names[safe: $0 - 1] }.joined(separator: " ")
    }

    public static func clock(_ minuteOfDay: Int) -> String {
        let h = (minuteOfDay / 60) % 24
        let m = minuteOfDay % 60
        let suffix = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d %@", h12, m, suffix)
    }

    public static func duration(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let h = minutes / 60
            return h == 1 ? "1 hour" : "\(h) hours"
        }
        return "\(minutes) min"
    }
}

nonisolated extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
