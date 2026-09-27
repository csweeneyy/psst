import Foundation

/// How much a habit is worth, chosen at setup.
nonisolated public enum HabitPriority: String, CaseIterable, Identifiable, Sendable {
    case low, normal, high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    public var points: Int {
        switch self {
        case .low: 5
        case .normal: 10
        case .high: 25
        }
    }

    /// Nearest priority to a stored value, so a habit edited by the assistant
    /// with an arbitrary number still shows a sensible selection.
    public static func nearest(to points: Int) -> HabitPriority {
        allCases.min { abs($0.points - points) < abs($1.points - points) } ?? .normal
    }
}

nonisolated public struct DayScore: Sendable, Equatable {
    public var day: Date
    public var base: Int
    public var multiplier: Double
    public var total: Int
}
