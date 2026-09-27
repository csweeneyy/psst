import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// The `alarm` tier.
///
/// AlarmKit is the only public iOS API that renders app-defined buttons with no
/// long press *and* overrides Focus and silent mode. It keeps its own recurring
/// schedule, so an every-weekday-at-7am habit is a single alarm rather than one
/// request per occurrence, and it never touches the 64 notification budget.
nonisolated enum AlarmService {

    /// AlarmKit throws `maximumLimitReached` at an undocumented ceiling. We
    /// stay conservative and surface a clear error rather than failing silently.
    static let maxAlarms = 8

    enum ServiceError: Error {
        case notAuthorized
        case limitReached
        case underlying(Error)
    }

    static var authorization: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func requestAuthorization() async -> Result<Bool, ServiceError> {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return .success(state == .authorized)
        } catch {
            return .failure(.underlying(error))
        }
    }

    static func cancelAll() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms { try? AlarmManager.shared.cancel(id: alarm.id) }
    }

    /// One alarm per distinct clock time per habit, recurring on the habit's
    /// weekdays. Deterministic ids so a resync replaces rather than duplicates.
    /// Clock times are taken from the plan, not recomputed from each habit.
    ///
    /// The plan has already resolved collisions across every tier, so an alarm
    /// that wanted the same minute as a Lock Screen card has been pushed to
    /// follow it. Recomputing here would undo that and let two alarms go off
    /// together.
    static func sync(
        _ habits: [Habit],
        plan: NudgePlan,
        calendar: Calendar = .current
    ) async -> Result<Int, ServiceError> {
        guard authorization == .authorized else { return .failure(.notAuthorized) }
        cancelAll()

        var plannedMinutes: [UUID: Set<Int>] = [:]
        for nudge in plan.alarms {
            let parts = calendar.dateComponents([.hour, .minute], from: nudge.fireAt)
            plannedMinutes[nudge.habitID, default: []]
                .insert((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }

        var count = 0
        for habit in habits where habit.intensity == .alarm && !habit.isPaused {
            let schedule = habit.schedule
            let minutes = (plannedMinutes[habit.id].map { Array($0).sorted() } ?? [])
                .isEmpty
                ? SchedulingService.minuteOffsets(
                    for: schedule, calendar: calendar, day: calendar.startOfDay(for: .now)
                )
                : Array(plannedMinutes[habit.id] ?? []).sorted()
            let weekdays = schedule.weekdays.sorted().compactMap(Self.weekday)

            for minute in minutes {
                guard count < maxAlarms else { return .failure(.limitReached) }

                let relative = Alarm.Schedule.Relative(
                    time: .init(hour: minute / 60, minute: minute % 60),
                    repeats: weekdays.isEmpty ? .never : .weekly(weekdays)
                )
                let attributes = AlarmAttributes<PsstAlarmMetadata>(
                    presentation: AlarmPresentation(alert: alert(for: habit)),
                    metadata: PsstAlarmMetadata(
                        habitID: habit.id, habitName: habit.name, symbol: habit.symbol
                    ),
                    tintColor: Color(hex: habit.tintHex)
                )
                let occurrenceID = UUID()
                let configuration = AlarmManager.AlarmConfiguration.alarm(
                    schedule: .relative(relative),
                    attributes: attributes,
                    stopIntent: CompleteHabitIntent(habitID: habit.id, occurrenceID: occurrenceID),
                    secondaryIntent: SnoozeHabitIntent(habitID: habit.id, occurrenceID: occurrenceID),
                    sound: .default
                )

                do {
                    _ = try await AlarmManager.shared.schedule(
                        id: alarmID(habit: habit.id, minute: minute),
                        configuration: configuration
                    )
                    count += 1
                } catch AlarmManager.AlarmError.maximumLimitReached {
                    return .failure(.limitReached)
                } catch {
                    return .failure(.underlying(error))
                }
            }
        }
        return .success(count)
    }

    /// A single alarm at one moment, separate from the habit's recurring set.
    /// Used by the preview, which must not disturb the real schedule.
    static func scheduleOneOff(
        habit: Habit,
        occurrenceID: UUID,
        at fireAt: Date
    ) async -> Result<Void, ServiceError> {
        let attributes = AlarmAttributes<PsstAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert(for: habit)),
            metadata: PsstAlarmMetadata(
                habitID: habit.id, habitName: habit.name, symbol: habit.symbol
            ),
            tintColor: Color(hex: habit.tintHex)
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(fireAt),
            attributes: attributes,
            stopIntent: CompleteHabitIntent(habitID: habit.id, occurrenceID: occurrenceID),
            secondaryIntent: SnoozeHabitIntent(habitID: habit.id, occurrenceID: occurrenceID),
            sound: .default
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            return .success(())
        } catch AlarmManager.AlarmError.maximumLimitReached {
            return .failure(.limitReached)
        } catch {
            return .failure(.underlying(error))
        }
    }

    /// The secondary button is `.custom` so Snooze runs our intent and writes a
    /// real skip to the store, instead of AlarmKit's opaque built-in countdown.
    private static func alert(for habit: Habit) -> AlarmPresentation.Alert {
        let title = LocalizedStringResource(stringLiteral: habit.nudgeCopy())
        let snooze = AlarmButton(
            text: "\(FollowUp.delayMinutes) min", textColor: .white, systemImageName: "clock"
        )
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: title,
                secondaryButton: snooze,
                secondaryButtonBehavior: .custom
            )
        } else {
            return AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"),
                secondaryButton: snooze,
                secondaryButtonBehavior: .custom
            )
        }
    }

    /// Stable UUID derived from the habit and the clock time, so re-syncing the
    /// same schedule reuses the same alarm slot.
    private static func alarmID(habit: UUID, minute: Int) -> UUID {
        var bytes = withUnsafeBytes(of: habit.uuid) { Array($0) }
        bytes[14] = UInt8(minute >> 8 & 0xFF)
        bytes[15] = UInt8(minute & 0xFF)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// `Calendar` weekdays are 1-indexed from Sunday.
    private static func weekday(_ index: Int) -> Locale.Weekday? {
        switch index {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
