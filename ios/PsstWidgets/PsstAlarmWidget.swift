import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit renders its own alert chrome, but it requires the app to ship a
/// widget extension registering the attributes type. Without this the system
/// can dismiss alarms without ever alerting.
struct PsstAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PsstAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.metadata?.symbol ?? "alarm")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    if let name = context.attributes.metadata?.habitName {
                        Text(name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            } compactLeading: {
                Image(systemName: context.attributes.metadata?.symbol ?? "alarm")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Image(systemName: "waveform")
                    .foregroundStyle(context.attributes.tintColor)
            } minimal: {
                Image(systemName: "alarm")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }
}
