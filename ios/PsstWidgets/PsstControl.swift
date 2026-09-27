import AppIntents
import SwiftUI
import WidgetKit

/// Control Centre, Lock Screen, and the Action button.
///
/// `IntentAuthenticationPolicy.alwaysAllowed` is what makes a press work on a
/// locked phone. Logging a habit is not security sensitive, and requiring a
/// Face ID glance would defeat the point of a physical button.
struct PsstLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PsstLogControl") {
            ControlWidgetButton(action: CompleteNextHabitIntent()) {
                Label("Log habit", systemImage: "checkmark.circle")
            }
        }
        .displayName("Log habit")
        .description("Marks whatever nudge is due as done.")
    }
}
