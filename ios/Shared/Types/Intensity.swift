import Foundation

/// How hard a habit is allowed to interrupt you.
///
/// The three cases map onto three genuinely different iOS surfaces, not three
/// cosmetic settings:
///
/// - `gentle`  -> `UNNotificationRequest`. Action buttons only appear when the
///                banner is expanded, which Apple provides no API to change.
/// - `standard`-> ActivityKit Live Activity. Buttons render inline on the Lock
///                Screen with no long press.
/// - `alarm`   -> AlarmKit. Overrides Focus and silent mode. iOS 26.0+.
nonisolated public enum Intensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case gentle
    case standard
    case alarm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .alarm: "Alarm"
        }
    }

    public var blurb: String {
        switch self {
        case .gentle: "Quiet banner. Respects Focus."
        case .standard: "Buttons on the Lock Screen."
        case .alarm: "Breaks through silent and Focus."
        }
    }

    public var symbol: String {
        switch self {
        case .gentle: "leaf"
        case .standard: "bell"
        case .alarm: "alarm.waves.left.and.right"
        }
    }
}
