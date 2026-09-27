import DeviceActivity
import Foundation

/// Raises the shield at the habit's time with the app not running.
///
/// This is the whole reason the extension exists. Nothing in the app is
/// guaranteed to be alive at 7am, but the system wakes this when a monitored
/// interval starts, and a `ManagedSettingsStore` written from here applies
/// device-wide immediately.
nonisolated class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let habit = Lockdown.habitID(fromActivity: activity.rawValue) else { return }
        let name = Lockdown.enabledNames()[habit.uuidString] ?? "your habit"
        LockdownService.raise(habit: habit, name: name)
    }

    /// The safety net. Whatever happened in between, the window ending takes
    /// the phone back. Without this a deleted habit or a crashed extension
    /// would leave the device shielded with nothing able to lift it.
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let habit = Lockdown.habitID(fromActivity: activity.rawValue) else { return }
        LockdownService.lower(ifHolding: habit)
    }
}
