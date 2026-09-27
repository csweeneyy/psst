import ActivityKit
import Foundation

/// The Live Activity backing the `standard` intensity tier.
nonisolated public struct NudgeAttributes: ActivityAttributes {
    nonisolated public struct ContentState: Codable, Hashable {
        public var answered: Bool
        public var snoozedUntil: Date?
        public init(answered: Bool = false, snoozedUntil: Date? = nil) {
            self.answered = answered
            self.snoozedUntil = snoozedUntil
        }
    }

    public var habitID: UUID
    public var occurrenceID: UUID
    public var habitName: String
    public var nudgeText: String
    public var symbol: String
    public var tintHex: String

    public init(
        habitID: UUID,
        occurrenceID: UUID,
        habitName: String,
        nudgeText: String,
        symbol: String,
        tintHex: String
    ) {
        self.habitID = habitID
        self.occurrenceID = occurrenceID
        self.habitName = habitName
        self.nudgeText = nudgeText
        self.symbol = symbol
        self.tintHex = tintHex
    }
}
