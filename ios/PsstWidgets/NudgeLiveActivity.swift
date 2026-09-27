import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The `standard` tier's Lock Screen card.
///
/// Everything here is visible without a long press, which is the entire reason
/// this tier exists. Buttons are bound to `LiveActivityIntent`s so a tap runs
/// in the app's process without opening the app.
struct NudgeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NudgeAttributes.self) { context in
            lockScreen(context)
                // No `activityBackgroundTint`. The system material already
                // adapts to the Lock Screen, and forcing white produced white
                // text on a white card in the dark appearance.
                .activitySystemActionForegroundColor(Color(hex: context.attributes.tintHex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    icon(context).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.nudgeText)
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.answered { resolved(context) } else { buttons(context) }
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(Color(hex: context.attributes.tintHex))
            } compactTrailing: {
                Image(systemName: context.state.answered ? "checkmark" : "bell.badge")
                    .foregroundStyle(Color(hex: context.attributes.tintHex))
            } minimal: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(Color(hex: context.attributes.tintHex))
            }
        }
    }

    private func icon(_ context: ActivityViewContext<NudgeAttributes>) -> some View {
        let tint = Color(hex: context.attributes.tintHex)
        return Image(systemName: context.attributes.symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.opacity(0.18)))
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<NudgeAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                icon(context)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.nudgeText)
                        .font(.system(size: 16, weight: .semibold))
                        // `.primary` follows the Lock Screen appearance, which
                        // is what makes this legible in both schemes.
                        .foregroundStyle(.primary)
                    Text(context.attributes.habitName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ZStack {
                if context.state.answered {
                    resolved(context)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    buttons(context)
                        .transition(.opacity)
                }
            }
            // The gap between the tap and the state arriving is a background
            // app launch, which iOS 26 gives no way to avoid. Animating the
            // swap turns a freeze into a transition.
            .animation(.snappy(duration: 0.28, extraBounce: 0), value: context.state.answered)
        }
        .padding(15)
    }

    private func resolved(_ context: ActivityViewContext<NudgeAttributes>) -> some View {
        Label(
            context.state.snoozedUntil == nil ? "Logged" : "Snoozed",
            systemImage: context.state.snoozedUntil == nil ? "checkmark.circle.fill" : "moon.zzz.fill"
        )
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color(hex: context.attributes.tintHex))
    }

    private func buttons(_ context: ActivityViewContext<NudgeAttributes>) -> some View {
        HStack(spacing: 8) {
            Button(intent: SnoozeHabitIntent(
                habitID: context.attributes.habitID,
                occurrenceID: context.attributes.occurrenceID
            )) {
                Text("\(FollowUp.delayMinutes)m")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.quaternary)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            // Toggle, not Button: it repaints the moment you tap it instead
            // of waiting for the app process to launch and run the intent.
            Toggle(
                isOn: context.state.answered,
                intent: CompleteHabitIntent(
                    habitID: context.attributes.habitID,
                    occurrenceID: context.attributes.occurrenceID
                )
            ) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color(hex: context.attributes.tintHex))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
        }
        // Marks the row as awaiting sync, so the wait reads as work in
        // progress rather than a dead control.
        .invalidatableContent()
    }
}
