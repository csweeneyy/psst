import Foundation

/// Bridges between "minutes from local midnight", which is how schedules are
/// stored, and `Date`, which is what `DatePicker` speaks. One place, because
/// every picker in the app needs the same conversion.
nonisolated public enum MinuteOfDay {
    public static func date(_ minute: Int, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: min(max(minute, 0), 1439), to: base) ?? base
    }

    public static func minutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
