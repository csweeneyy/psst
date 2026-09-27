import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Turning the phone into a single-purpose device until a habit is done.
///
/// Three moving parts, because Apple splits them across three processes:
///
///   1. `DeviceActivityCenter` schedules a window per habit. Its monitor
///      extension is woken at the start of that window with the app not
///      running, which is the only way a 7am lockdown can work.
///   2. `ManagedSettingsStore` holds the shield itself.
///   3. A shield action extension owns the button on the blocking screen.
///
/// This type is the app's side: asking for permission, keeping the schedules in
/// sync with the habits, and lifting a shield when the habit is completed
/// somewhere other than the shield screen.
nonisolated public enum LockdownService {
    public enum Failure: Error, LocalizedError {
        case denied
        case unavailable(String)

        public var errorDescription: String? {
            switch self {
            case .denied:
                "Psst needs Screen Time access to lock your phone during a habit."
            case .unavailable(let reason):
                reason
            }
        }
    }

    public static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Individual authorization: this device, this person, no family setup and
    /// no parent account. The user confirms with Face ID.
    public static func authorize() async -> Failure? {
        if isAuthorized { return nil }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return isAuthorized ? nil : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - The shield itself

    private static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(Lockdown.storeName))
    }

    /// Shield everything.
    ///
    /// `.all(except: [])` covers every app category on the device. Psst is
    /// exempt automatically, which is what makes the unlock reachable. The
    /// Home Screen, Settings and anything the user has put in Screen Time's
    /// Always Allowed can never be covered, so this is a strong nudge rather
    /// than a cage, and it is described that way in the UI.
    public static func raise(habit: UUID, name: String) {
        let store = store
        store.shield.applicationCategories = .all(except: [])
        store.shield.webDomainCategories = .all(except: [])
        Lockdown.begin(habit: habit, name: name)
    }

    public static func lower() {
        store.clearAllSettings()
        Lockdown.end()
    }

    /// Lower the shield only if it is standing for this particular habit, so
    /// completing an unrelated habit cannot unlock the phone.
    public static func lower(ifHolding habit: UUID) {
        guard Lockdown.activeHabit() == habit else { return }
        lower()
    }

    // MARK: - Schedules

    /// Bring the scheduled windows in line with the habits.
    ///
    /// One activity per locking habit, keyed by habit id, so re-syncing is
    /// idempotent and deleting a habit removes its window. `DeviceActivity`
    /// caps a device at 20 concurrent activities; locking habits are rare
    /// enough that taking the first few is honest rather than arbitrary.
    public static func sync(_ habits: [(id: UUID, name: String, minute: Int, enabled: Bool)]) {
        let center = DeviceActivityCenter()
        let wanted = habits.filter(\.enabled).prefix(20)

        for activity in center.activities {
            guard let id = Lockdown.habitID(fromActivity: activity.rawValue) else { continue }
            if !wanted.contains(where: { $0.id == id }) {
                center.stopMonitoring([activity])
            }
        }

        var names: [String: String] = [:]
        for habit in wanted {
            names[habit.id.uuidString] = habit.name
            let start = DateComponents(hour: habit.minute / 60, minute: habit.minute % 60)
            let endMinute = (habit.minute + Lockdown.maximumMinutes) % (24 * 60)
            let end = DateComponents(hour: endMinute / 60, minute: endMinute % 60)

            let schedule = DeviceActivitySchedule(
                intervalStart: start,
                intervalEnd: end,
                repeats: true
            )
            let activity = DeviceActivityName(Lockdown.activityName(for: habit.id))
            center.stopMonitoring([activity])
            try? center.startMonitoring(activity, during: schedule)
        }
        Lockdown.setEnabled(names)
    }

    /// Arms a one-off window so a previewed nudge locks the phone exactly the
    /// way the real one will.
    ///
    /// Testing the lockdown separately from the nudge was the wrong call: it
    /// meant the thing being demonstrated was not the thing that ships. A
    /// `DeviceActivitySchedule` is wall-clock and its interval has a fifteen
    /// minute floor, so a preview thirty seconds out arms the window at the
    /// current minute. The monitor extension then raises the shield as the
    /// nudge lands.
    public static func arm(habit: UUID, name: String, at date: Date) {
        guard isAuthorized else { return }

        var names = Lockdown.enabledNames()
        names[habit.uuidString] = name
        Lockdown.setEnabled(names)

        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let endMinute = (minute + Lockdown.maximumMinutes) % (24 * 60)

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: minute / 60, minute: minute % 60),
            intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
            repeats: false
        )
        let activity = DeviceActivityName(Lockdown.activityName(for: habit))
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        try? center.startMonitoring(activity, during: schedule)
    }

    public static func stopAll() {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities)
        Lockdown.setEnabled([:])
        lower()
    }
}
