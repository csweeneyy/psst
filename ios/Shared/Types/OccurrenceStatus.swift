import Foundation

nonisolated public enum OccurrenceStatus: String, Codable, Sendable {
    case pending
    case completed
    case skipped
    /// The window passed with no answer at all.
    case missed
}
