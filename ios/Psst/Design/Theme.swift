import SwiftUI

/// One vocabulary for the whole app.
///
/// Deliberately built on UIKit's semantic colours rather than hand-picked hex.
/// Those are the exact values Settings, Mail and Reminders draw with, they
/// track the system's contrast and accessibility settings for free, and they
/// are the single biggest reason an app reads as native rather than themed.
nonisolated public enum Theme {

    // MARK: Colour

    public enum Palette {
        /// Grouped-list background. White cards sit on this.
        public static let canvas = Color(uiColor: .systemGroupedBackground)
        public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        /// Inset controls inside a card.
        public static let well = Color(uiColor: .tertiarySystemGroupedBackground)
        public static let hairline = Color(uiColor: .separator)

        public static let ink = Color(uiColor: .label)
        public static let inkSoft = Color(uiColor: .secondaryLabel)
        public static let inkFaint = Color(uiColor: .tertiaryLabel)

        /// Near-black. Colour is reserved for state, not decoration.
        public static let accent = Color(uiColor: .label)
        public static let onAccent = Color(uiColor: .systemBackground)

        public static let success = Color(uiColor: .systemGreen)
        public static let alarm = Color(uiColor: .systemRed)
        public static let warning = Color(uiColor: .systemOrange)
    }

    // MARK: Spacing

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 36
    }

    // MARK: Shape

    public enum Radius {
        /// Matches the inset grouped list corner radius.
        public static let card: CGFloat = 12
        public static let control: CGFloat = 10
        public static let sheet: CGFloat = 16
    }

    // MARK: Motion

    /// `.snappy` settles roughly twice as fast as a default spring and has
    /// almost no overshoot. Overshoot is what made the old build feel slow.
    public static let motion = Animation.snappy(duration: 0.22, extraBounce: 0)
    public static let fast = Animation.snappy(duration: 0.13, extraBounce: 0)

    // MARK: Type

    /// SF Pro, with the negative tracking Apple applies at display sizes.
    /// No rounded design: SF Rounded is Apple's playful face and reads as toy
    /// UI outside Fitness and Kids content.
    public static func largeTitle(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold)
    }
    public static func title(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }
    public static func body(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular)
    }
    public static func footnote(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular)
    }
    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }
    /// Tabular figures, so streak and percentage counters do not jitter.
    public static func number(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }

    public static let displayTracking: CGFloat = -0.5
}

// MARK: - Card

/// Flat white on grey, exactly like an inset grouped list section.
///
/// The previous version stacked two shadow layers plus a stroked overlay on
/// every card. Each shadow forces an offscreen render pass, and there were
/// dozens of cards on screen. Dropping them is both faster and closer to how
/// Apple actually draws lists.
public struct CardBackground: ViewModifier {
    var tint: Color = Theme.Palette.surface

    public func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint)
        )
    }
}

public extension View {
    func card(tint: Color = Theme.Palette.surface) -> some View {
        modifier(CardBackground(tint: tint))
    }

    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }

    /// Large titles only. Body text at the system tracking is correct as-is.
    func displayTracking() -> some View {
        tracking(Theme.displayTracking)
    }
}

public struct PressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(Theme.fast, value: configuration.isPressed)
    }
}
