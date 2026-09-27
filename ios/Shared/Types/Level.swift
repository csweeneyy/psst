import Foundation

/// What points accumulate into.
///
/// Deliberately has no names. An earlier version called the tiers Quiet,
/// Listening, Answering, Steady, Reliable and Unmissable, which forced the UI
/// to write sentences like "55 to Listening": a label nobody can read a
/// meaning off without being taught the ladder first. A bar between the number
/// you have and the number you are heading for explains itself.
///
/// The ladder still widens as it climbs, so early progress feels quick and
/// later progress is earned.
nonisolated public enum Level: Sendable {
    public static let thresholds: [Int] = [0, 150, 450, 1000, 2000, 4000, 7500, 12000]

    /// The threshold you have already passed.
    public static func floor(for points: Int) -> Int {
        thresholds.last { points >= $0 } ?? 0
    }

    /// The threshold you are heading for. Past the top of the ladder it keeps
    /// going in steps the same size as the last one, so the bar never jams
    /// full and stops meaning anything.
    public static func ceiling(for points: Int) -> Int {
        if let next = thresholds.first(where: { $0 > points }) { return next }
        let step = thresholds[thresholds.count - 1] - thresholds[thresholds.count - 2]
        let over = points - thresholds[thresholds.count - 1]
        return thresholds[thresholds.count - 1] + step * (over / step + 1)
    }

    /// 0 to 1 between those two numbers.
    public static func progress(for points: Int) -> Double {
        let low = floor(for: points), high = ceiling(for: points)
        guard high > low else { return 1 }
        return min(max(Double(points - low) / Double(high - low), 0), 1)
    }
}
