import Foundation

/// Everything the app and its three lockdown extensions have to agree on.
///
/// The extensions are separate processes with their own sandboxes. They cannot
/// see SwiftData, so every fact that has to cross the boundary crosses it as
/// plain values in the shared defaults, and this is the only place those keys
/// are written down.
nonisolated public enum Lockdown {
    /// The one place this string is written down. The extensions are built
    /// from only this file and `LockdownService`, so it cannot live in the
    /// SwiftData model the way it used to.
    public static let appGroup = "group.com.connorsweeney.Psst"
    /// The managed settings store the shield lives in. Named, not the default
    /// one, so clearing it cannot disturb anything else on the device.
    public static let storeName = "psst.lockdown"

    /// The habit currently holding the phone, if any.
    public static let activeHabitKey = "lockdown.activeHabit"
    public static let activeHabitNameKey = "lockdown.activeHabitName"
    public static let activeSinceKey = "lockdown.activeSince"

    /// Habit ids the shield screen marked done, waiting for the app to open
    /// and write them into the store properly.
    public static let completionsKey = "lockdown.completions"

    /// Habits with lockdown turned on, as id to name, so the monitor extension
    /// knows what it is shielding for without reading SwiftData.
    public static let enabledKey = "lockdown.enabled"

    /// The longest a shield may stand. A crash, a deleted habit or a schedule
    /// change must never leave the phone bricked, so every activity ends on its
    /// own even if nothing ever completes it.
    public static let maximumMinutes = 90

    public static func activityName(for habit: UUID) -> String {
        "psst.lockdown.\(habit.uuidString)"
    }

    public static func habitID(fromActivity name: String) -> UUID? {
        guard name.hasPrefix("psst.lockdown.") else { return nil }
        return UUID(uuidString: String(name.dropFirst("psst.lockdown.".count)))
    }

    // MARK: - Shared state

    public static func begin(habit: UUID, name: String, in defaults: UserDefaults = .psst) {
        defaults.set(habit.uuidString, forKey: activeHabitKey)
        defaults.set(name, forKey: activeHabitNameKey)
        defaults.set(Date.now, forKey: activeSinceKey)
    }

    public static func end(in defaults: UserDefaults = .psst) {
        defaults.removeObject(forKey: activeHabitKey)
        defaults.removeObject(forKey: activeHabitNameKey)
        defaults.removeObject(forKey: activeSinceKey)
    }

    public static func activeHabit(in defaults: UserDefaults = .psst) -> UUID? {
        guard let raw = defaults.string(forKey: activeHabitKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func activeName(in defaults: UserDefaults = .psst) -> String {
        defaults.string(forKey: activeHabitNameKey) ?? "your habit"
    }

    /// Recorded by the shield screen, drained by the app. An array rather than
    /// a single value because the app may not run for a while.
    public static func recordCompletion(habit: UUID, in defaults: UserDefaults = .psst) {
        var pending = defaults.stringArray(forKey: completionsKey) ?? []
        pending.append(habit.uuidString)
        defaults.set(pending, forKey: completionsKey)
    }

    public static func drainCompletions(in defaults: UserDefaults = .psst) -> [UUID] {
        let pending = defaults.stringArray(forKey: completionsKey) ?? []
        guard !pending.isEmpty else { return [] }
        defaults.removeObject(forKey: completionsKey)
        return pending.compactMap(UUID.init(uuidString:))
    }

    public static func setEnabled(_ names: [String: String], in defaults: UserDefaults = .psst) {
        defaults.set(names, forKey: enabledKey)
    }

    public static func enabledNames(in defaults: UserDefaults = .psst) -> [String: String] {
        defaults.dictionary(forKey: enabledKey) as? [String: String] ?? [:]
    }
}

extension UserDefaults {
    /// Shared with the widget and the lockdown extensions.
    ///
    /// `UserDefaults` is thread safe but not `Sendable`, and this is only ever
    /// assigned once, so the unchecked annotation is accurate rather than a
    /// silencer.
    nonisolated(unsafe) public static let psst =
        UserDefaults(suiteName: Lockdown.appGroup) ?? .standard
}
