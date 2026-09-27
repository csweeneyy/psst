import SwiftUI

/// The visual vocabulary of a habit, in one place.
///
/// Symbols, tints and the default colour were previously repeated across the
/// setup screen, both row types, the calendar, the widget, the sample data and
/// the model's own default. Six copies of one decision is five chances for
/// them to disagree.
nonisolated public enum HabitStyle {
    public static let defaultTintHex = "#007AFF"
    public static let defaultSymbol = "circle.dashed"

    /// iOS system colours, so a habit tint always looks native.
    public static let tints = [
        "#007AFF",  // blue
        "#34C759",  // green
        "#5856D6",  // indigo
        "#FF9500",  // orange
        "#FF2D55",  // pink
        "#30B0C7",  // teal
    ]

    public static let symbols = [
        "figure.stand", "drop", "figure.walk", "book", "dumbbell",
        "moon.zzz", "pills", "eye", "leaf", "brain.head.profile",
    ]

    public static func tint(_ hex: String?) -> Color {
        Color(hex: hex ?? defaultTintHex)
    }
}

nonisolated public extension Intensity {
    /// How loudly this tier reads. Used by every surface that shows a tier.
    var accent: Color {
        switch self {
        case .gentle: Color(uiColor: .systemGreen)
        case .standard: Color(uiColor: .label)
        case .alarm: Color(uiColor: .systemRed)
        }
    }
}

nonisolated public extension OccurrenceStatus {
    var symbol: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .skipped: "moon.zzz.fill"
        case .missed: "exclamationmark.circle.fill"
        case .pending: "circle"
        }
    }

    var accent: Color {
        switch self {
        case .completed: Color(uiColor: .systemGreen)
        case .skipped: Color(uiColor: .tertiaryLabel)
        case .missed: Color(uiColor: .systemRed)
        case .pending: Color(uiColor: .tertiaryLabel)
        }
    }
}
