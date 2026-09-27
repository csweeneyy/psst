import SwiftUI

/// The bird.
///
/// Drawn in SwiftUI shapes rather than shipped as artwork, for three reasons:
/// it scales to any size without assets, it inherits the app's ink colour so
/// it belongs to the same design system as the SF Symbols beside it, and its
/// posture can be driven by state rather than swapped between images.
///
/// Deliberately geometric and monochrome. A full-colour illustrated pet would
/// be warmer, and would also be a hard tonal break from an app built out of
/// graphite and SF Pro.
struct MascotView: View {
    var mood: Mood
    var size: CGFloat = 44

    enum Mood: Equatable {
        /// Nothing owed, nothing missed.
        case calm
        /// On a streak. Chest out.
        case proud
        /// Something is due right now.
        case alert
        /// Missed the last one.
        case slumped

        /// Body tilt in degrees. Negative leans back and up.
        var tilt: Double {
            switch self {
            case .calm: 0
            case .proud: -8
            case .alert: -3
            case .slumped: 11
            }
        }

        var lift: CGFloat {
            switch self {
            case .proud: -0.05
            case .slumped: 0.045
            default: 0
            }
        }

        /// Open beak for alert, so a due nudge reads at a glance.
        var beakOpen: Bool { self == .alert }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let ink = Theme.Palette.ink

            context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2 + mood.lift * s)
            context.rotate(by: .degrees(mood.tilt))
            context.translateBy(x: -s / 2, y: -s / 2)

            // Body: a teardrop leaning forward, tail to the left.
            var body = Path()
            body.move(to: CGPoint(x: s * 0.30, y: s * 0.86))
            body.addCurve(
                to: CGPoint(x: s * 0.74, y: s * 0.50),
                control1: CGPoint(x: s * 0.06, y: s * 0.80),
                control2: CGPoint(x: s * 0.10, y: s * 0.34)
            )
            body.addCurve(
                to: CGPoint(x: s * 0.30, y: s * 0.86),
                control1: CGPoint(x: s * 0.96, y: s * 0.62),
                control2: CGPoint(x: s * 0.70, y: s * 0.94)
            )
            context.fill(body, with: .color(ink))

            // Tail, a clipped wedge off the back.
            var tail = Path()
            tail.move(to: CGPoint(x: s * 0.26, y: s * 0.60))
            tail.addLine(to: CGPoint(x: s * 0.02, y: s * 0.44))
            tail.addLine(to: CGPoint(x: s * 0.20, y: s * 0.78))
            tail.closeSubpath()
            context.fill(tail, with: .color(ink))

            // Head.
            let head = CGRect(x: s * 0.52, y: s * 0.16, width: s * 0.36, height: s * 0.36)
            context.fill(Path(ellipseIn: head), with: .color(ink))

            // Beak.
            var beak = Path()
            let bx = s * 0.86, by = s * 0.33
            beak.move(to: CGPoint(x: bx, y: by - s * 0.045))
            beak.addLine(to: CGPoint(x: bx + s * 0.13, y: by + (mood.beakOpen ? s * 0.02 : s * 0.005)))
            beak.addLine(to: CGPoint(x: bx, y: by + s * 0.045))
            beak.closeSubpath()
            context.fill(beak, with: .color(ink))

            if mood.beakOpen {
                var lower = Path()
                lower.move(to: CGPoint(x: bx, y: by + s * 0.045))
                lower.addLine(to: CGPoint(x: bx + s * 0.10, y: by + s * 0.10))
                lower.addLine(to: CGPoint(x: bx, y: by + s * 0.085))
                lower.closeSubpath()
                context.fill(lower, with: .color(ink))
            }

            // Eye, punched out so it reads at any size.
            let eye = CGRect(x: s * 0.70, y: s * 0.26, width: s * 0.085, height: s * 0.085)
            context.blendMode = .destinationOut
            context.fill(Path(ellipseIn: eye), with: .color(.black))
            context.blendMode = .normal

            // Wing, a lighter notch so the silhouette is not a solid blob.
            var wing = Path()
            wing.move(to: CGPoint(x: s * 0.32, y: s * 0.62))
            wing.addQuadCurve(
                to: CGPoint(x: s * 0.62, y: s * 0.66),
                control: CGPoint(x: s * 0.46, y: s * 0.48)
            )
            wing.addQuadCurve(
                to: CGPoint(x: s * 0.32, y: s * 0.62),
                control: CGPoint(x: s * 0.46, y: s * 0.80)
            )
            context.opacity = 0.34
            context.blendMode = .destinationOut
            context.fill(wing, with: .color(.black))
            context.blendMode = .normal
            context.opacity = 1
        }
        .frame(width: size, height: size)
        .animation(Theme.motion, value: mood)
        .accessibilityHidden(true)
    }
}

/// Works out how the bird should be standing.
nonisolated enum MascotMood {
    @MainActor
    static func current(
        habits: [Habit],
        occurrences: [HabitOccurrence],
        now: Date = .now
    ) -> MascotView.Mood {
        let calendar = Calendar.current
        let today = occurrences.filter {
            $0.habit != nil && calendar.isDateInToday($0.scheduledAt)
        }

        if today.contains(where: { $0.status == .pending && $0.scheduledAt <= now }) {
            return .alert
        }
        // A miss in the last few hours is what the bird reacts to. An old one
        // is history, not a mood.
        let recentMiss = today.contains {
            $0.status == .missed && now.timeIntervalSince($0.scheduledAt) < 4 * 3600
        }
        if recentMiss { return .slumped }

        let bestStreak = habits.map { HabitStatsService.streak(for: $0.occurrences, now: now) }.max() ?? 0
        return bestStreak >= 3 ? .proud : .calm
    }
}
