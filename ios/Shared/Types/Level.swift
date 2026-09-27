import Foundation

/// What points accumulate into.
///
/// Named rather than numbered, and describing the person rather than the
/// score: the point of a level here is to say something true about how you
/// have been behaving, not to be a bar that fills up.
nonisolated public struct Level: Sendable, Equatable, Identifiable {
    public var index: Int
    public var name: String
    public var threshold: Int

    public var id: Int { index }

    public static let all: [Level] = [
        Level(index: 0, name: "Quiet", threshold: 0),
        Level(index: 1, name: "Listening", threshold: 150),
        Level(index: 2, name: "Answering", threshold: 450),
        Level(index: 3, name: "Steady", threshold: 1000),
        Level(index: 4, name: "Reliable", threshold: 2000),
        Level(index: 5, name: "Unmissable", threshold: 4000),
    ]

    public static func current(for points: Int) -> Level {
        all.last { points >= $0.threshold } ?? all[0]
    }

    public static func next(after level: Level) -> Level? {
        all.first { $0.index == level.index + 1 }
    }

    /// 0 to 1 through the current level. The top level always reads full.
    public static func progress(for points: Int) -> Double {
        let level = current(for: points)
        guard let next = next(after: level) else { return 1 }
        let span = Double(next.threshold - level.threshold)
        guard span > 0 else { return 1 }
        return min(max(Double(points - level.threshold) / span, 0), 1)
    }

    public static func pointsToNext(from points: Int) -> Int? {
        guard let next = next(after: current(for: points)) else { return nil }
        return max(next.threshold - points, 0)
    }
}
