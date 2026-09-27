import AppIntents
import SwiftUI
import WidgetKit

struct NextNudgeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NextNudgeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextNudgeEntry {
        NextNudgeEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextNudgeEntry) -> Void) {
        Task { @MainActor in
            completion(NextNudgeEntry(
                date: .now,
                snapshot: context.isPreview ? .placeholder : WidgetSnapshot.current()
            ))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextNudgeEntry>) -> Void) {
        Task { @MainActor in
            let snapshot = WidgetSnapshot.current()
            var entries = [NextNudgeEntry(date: .now, snapshot: snapshot)]

            // Re-render the moment the pending nudge becomes due, so the widget
            // flips to its "now" appearance without waiting for a refresh.
            if let fireAt = snapshot.fireAt, fireAt > .now {
                entries.append(NextNudgeEntry(date: fireAt, snapshot: snapshot))
            }
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct NextNudgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PsstNextNudge", provider: NextNudgeProvider()) { entry in
            NextNudgeView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "psst://home"))
        }
        .configurationDisplayName("Next nudge")
        .description("What is due. Tap to open Psst.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular,
        ])
    }
}

struct NextNudgeView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var tint: Color { Color(hex: snapshot.tintHex) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: snapshot.symbol)
            }
            .gaugeStyle(.accessoryCircularCapacity)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.habitName).font(.headline).lineLimit(1)
                Text(timeLabel).font(.caption)
                Text("\(snapshot.completedToday)/\(snapshot.scheduledToday) today").font(.caption2)
            }

        case .systemMedium:
            HStack(spacing: 14) {
                summary
                if snapshot.occurrenceID != nil {
                    completeButton.frame(width: 96)
                }
            }

        default:
            // Small carries no button on purpose. A control inside it would
            // swallow taps in its own area, and the whole point of the small
            // size is that tapping anywhere opens the app.
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: snapshot.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                Spacer()
                Text("\(snapshot.completedToday)/\(snapshot.scheduledToday)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(snapshot.habitName)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(timeLabel)
                .font(.system(size: 13))
                .foregroundStyle(snapshot.isDue ? tint : .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var completeButton: some View {
        if let habitID = snapshot.habitID, let occurrenceID = snapshot.occurrenceID {
            Button(intent: CompleteHabitIntent(habitID: habitID, occurrenceID: occurrenceID)) {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
        }
    }

    private var progress: Double {
        guard snapshot.scheduledToday > 0 else { return 0 }
        return Double(snapshot.completedToday) / Double(snapshot.scheduledToday)
    }

    private var timeLabel: String {
        guard let fireAt = snapshot.fireAt else { return "Nothing due" }
        if snapshot.isDue { return "Due now" }
        return fireAt.formatted(date: .omitted, time: .shortened)
    }
}
