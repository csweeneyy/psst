import Foundation
import SwiftData

@Model
public final class Habit {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// The exact words that show up on the Lock Screen. "Psst... check your posture :)"
    public var nudgeText: String
    public var intensityRaw: String
    public var scheduleData: Data
    public var isPaused: Bool
    public var createdAt: Date
    public var symbol: String
    public var tintHex: String
    /// Free text you keep with the habit. Why it matters, what counts as done.
    public var notes: String = ""
    /// Alternative phrasings, one per line.
    ///
    /// iOS exposes no way to vary a notification's vibration, so the only
    /// lever against "oh, it's that app again" is the words. A habit that says
    /// something slightly different each time stays readable for longer.
    public var nudgeVariantsRaw: String = ""
    /// What a full day of this habit is worth. Set by priority at setup.
    public var dailyPoints: Int = HabitPriority.normal.points

    @Relationship(deleteRule: .cascade, inverse: \HabitOccurrence.habit)
    public var occurrences: [HabitOccurrence]

    public init(
        id: UUID = UUID(),
        name: String,
        nudgeText: String,
        intensity: Intensity,
        schedule: Schedule,
        symbol: String = HabitStyle.defaultSymbol,
        tintHex: String = HabitStyle.defaultTintHex
    ) {
        self.id = id
        self.name = name
        self.nudgeText = nudgeText
        self.intensityRaw = intensity.rawValue
        self.scheduleData = (try? JSONEncoder().encode(schedule)) ?? Data()
        self.isPaused = false
        self.createdAt = .now
        self.symbol = symbol
        self.tintHex = tintHex
        self.notes = ""
        self.nudgeVariantsRaw = ""
        self.dailyPoints = HabitPriority.normal.points
        self.occurrences = []
    }

    /// Every phrasing this habit can use, primary first.
    public var nudgeVariants: [String] {
        [nudgeText] + nudgeVariantsRaw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A phrasing for one firing. Avoids repeating `previous` where it can, so
    /// two nudges in a row never read identically.
    public func nudgeCopy(avoiding previous: String? = nil) -> String {
        let options = nudgeVariants
        guard options.count > 1 else { return nudgeText }
        let candidates = options.filter { $0 != previous }
        return (candidates.isEmpty ? options : candidates).randomElement() ?? nudgeText
    }

    public var intensity: Intensity {
        get { Intensity(rawValue: intensityRaw) ?? .gentle }
        set { intensityRaw = newValue.rawValue }
    }

    /// Falls back to a two-hourly schedule rather than trapping, because a
    /// decode failure must never take down the whole Today screen.
    public var schedule: Schedule {
        get { (try? JSONDecoder().decode(Schedule.self, from: scheduleData)) ?? .everyTwoHours }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? scheduleData }
    }
}

@Model
public final class HabitOccurrence {
    @Attribute(.unique) public var id: UUID
    public var scheduledAt: Date
    public var statusRaw: String
    public var respondedAt: Date?
    public var snoozeCount: Int
    /// Set when you move this one nudge by hand. A pinned occurrence survives
    /// a resync untouched, so editing the habit's schedule never silently
    /// undoes a time you picked deliberately.
    public var isPinned: Bool = false
    /// Created by snoozing. Already has its own notification scheduled, so the
    /// coordinator must not schedule a second one for it.
    public var isFollowUp: Bool = false
    /// Nudges that wanted the same moment share a group and are answered in
    /// position order, one after another.
    public var queueGroup: UUID?
    public var queuePosition: Int = 0
    public var habit: Habit?

    public init(id: UUID = UUID(), scheduledAt: Date, habit: Habit?) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.statusRaw = OccurrenceStatus.pending.rawValue
        self.respondedAt = nil
        self.snoozeCount = 0
        self.isPinned = false
        self.isFollowUp = false
        self.queueGroup = nil
        self.queuePosition = 0
        self.habit = habit
    }

    public var status: OccurrenceStatus {
        get { OccurrenceStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
public final class ChatMessage {
    @Attribute(.unique) public var id: UUID
    public var roleRaw: String
    public var text: String
    public var createdAt: Date
    /// Human-readable list of what the assistant actually changed, so the
    /// transcript shows consequences and not just conversation.
    public var appliedSummary: String?

    public init(role: String, text: String, appliedSummary: String? = nil) {
        self.id = UUID()
        self.roleRaw = role
        self.text = text
        self.createdAt = .now
        self.appliedSummary = appliedSummary
    }

    public var isUser: Bool { roleRaw == "user" }
}

public enum PsstStore {
    public static let appGroup = "group.com.connorsweeney.Psst"

    public static let schema = Schema([Habit.self, HabitOccurrence.self, ChatMessage.self])

    /// Shared container so the widget extension and the app read the same rows.
    ///
    /// The app-group path is checked with `FileManager` first. SwiftData calls
    /// `fatalError` (not a throw) when asked for a group container the process
    /// is not entitled to, so `try?` alone would not save the launch. That
    /// happens on any unsigned build, including plain `xcodebuild` runs.
    /// Process-wide. Creating a second `ModelContainer` over the same store
    /// is legal but the two do not share a coordinator, so a write through one
    /// is invisible to the other until a refetch. That is what made the Live
    /// Activity buttons look dead: the intent wrote to a private container the
    /// running app was not observing.
    public static let shared: ModelContainer = container()

    public static func container() -> ModelContainer {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil {
            let shared = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
            if let container = try? ModelContainer(for: schema, configurations: shared) {
                return container
            }
        }
        // Process-local store. The app still works; only widget/app sharing is lost.
        if let local = try? ModelContainer(for: schema) { return local }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }
}
