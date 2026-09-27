import AlarmKit
import Foundation

/// AlarmKit requires a concrete `AlarmMetadata` type even when it carries
/// nothing the system itself reads. We use it to carry the habit back to the
/// intent that fires when a button is tapped.
nonisolated public struct PsstAlarmMetadata: AlarmMetadata {
    public var habitID: UUID
    public var habitName: String
    public var symbol: String

    public init(habitID: UUID, habitName: String, symbol: String) {
        self.habitID = habitID
        self.habitName = habitName
        self.symbol = symbol
    }
}
