import Foundation
import Testing
@testable import Psst

/// The assistant scheduled a habit for Sunday when it was Saturday evening,
/// because the app sent `ISO8601DateFormatter().string(from: .now)`, which is
/// GMT. At 8:26 PM Eastern on a Saturday that reads `2026-09-27T00:26:29Z`.
@Suite("Local time sent to the assistant")
struct LocalTimeTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test("Late Saturday in New York is described as Saturday, not Sunday")
    func doesNotRollOverToUTCDay() {
        let eastern = calendar("America/New_York")
        let saturdayEvening = eastern.date(
            from: DateComponents(year: 2026, month: 9, day: 26, hour: 20, minute: 26)
        )!
        // Sanity: this instant really is Sunday in UTC.
        #expect(calendar("UTC").component(.weekday, from: saturdayEvening) == 1)

        let description = AssistantService.localTimeDescription(saturdayEvening, calendar: eastern)
        #expect(description.hasPrefix("Saturday"))
        #expect(description.contains("weekday number 7"))
        #expect(!description.contains("Sunday"))
    }

    @Test("The spelled-out weekday matches the schedule tool's numbering")
    func weekdayNumbersMatchCalendar() {
        let utc = calendar("UTC")
        // 2026-03-01 is a Sunday, so weekday 1, through Saturday at 7.
        let expected = [
            (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
            (5, "Thursday"), (6, "Friday"), (7, "Saturday"),
        ]
        for (offset, pair) in expected.enumerated() {
            let day = utc.date(from: DateComponents(year: 2026, month: 3, day: 1 + offset, hour: 12))!
            #expect(utc.component(.weekday, from: day) == pair.0)
            let description = AssistantService.localTimeDescription(day, calendar: utc)
            #expect(description.hasPrefix(pair.1))
            #expect(description.contains("weekday number \(pair.0)"))
        }
    }
}
