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

    /// Shield every other app when this habit is due, until it is done.
    /// Defaulted so existing stores migrate without a schema version.
    public var lockdownEnabled: Bool = false

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
    /// Set once this nudge has had its own alert scheduled outside the regular
    /// plan, so a resync does not schedule it a second time.
    public var deliveryScheduled: Bool = false
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
        self.deliveryScheduled = false
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
    /// Plain data, so non-isolated code (alarm bookkeeping, the widget) can
    /// reach it without hopping to the main actor.
    nonisolated public static let appGroup = Lockdown.appGroup

    nonisolated public static let schema = Schema([Habit.self, HabitOccurrence.self, ChatMessage.self])

    /// True when `shared` is a throwaway store rather than the real one.
    ///
    /// Callers that write must check this. Saving an answer into a scratch
    /// container looks like it worked and silently drops the data.
    @MainActor public private(set) static var isDegraded = false

    @MainActor private static var cached: ModelContainer?

    /// The real store, or a scratch one if it genuinely cannot be opened.
    ///
    /// Deliberately NOT a `static let`. The app group container is protected
    /// by data protection: when iOS launches this process in the background to
    /// run an intent while the phone is locked, the store cannot be opened at
    /// all. Caching that failure for the lifetime of the process meant the
    /// user unlocked their phone, opened the app, and found every habit gone,
    /// while the real database sat untouched on disk.
    ///
    /// So a degraded container is never cached, and every access retries.
    @MainActor public static var shared: ModelContainer {
        if let cached { return cached }

        if let real = openGroupStore() {
            cached = real
            isDegraded = false
            return real
        }

        isDegraded = true
        psstLog.error("app group store unavailable; running on a scratch container")
        // Not cached: the next access, once the device is unlocked, gets the
        // real thing.
        return scratch()
    }

    private static func openGroupStore() -> ModelContainer? {
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
        else { return nil }
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
        return try? ModelContainer(for: schema, configurations: configuration)
    }

    private static func scratch() -> ModelContainer {
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }
}
