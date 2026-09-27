import SwiftData
import SwiftUI

struct HabitSetupView: View {
    let habit: Habit?
    let onSave: () async -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var nudgeText = ""
    @State private var intensity: Intensity = .standard
    @State private var mode: Mode = .interval
    @State private var intervalMinutes = 120
    @State private var perPeriodCount = 3
    @State private var period: Period = .day
    @State private var fixedTimes: [Int] = [9 * 60]
    @State private var windowStart = 9 * 60
    @State private var windowEnd = 21 * 60
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    @State private var symbol = "figure.stand"
    @State private var tintHex = "#007AFF"
    @State private var alarmDenied = false

    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case interval, times, fixed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .interval: "Every"
            case .times: "X per"
            case .fixed: "At"
            }
        }
    }

    private static let symbols = [
        "figure.stand", "drop", "figure.walk", "book", "dumbbell",
        "moon.zzz", "pills", "eye", "leaf", "brain.head.profile",
    ]
    /// System colours, so a habit tint always looks like it belongs to iOS.
    private static let tints = ["#007AFF", "#34C759", "#5856D6", "#FF9500", "#FF2D55", "#30B0C7"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    identity
                    nudgeCopy
                    intensitySection
                    cadence
                    window
                    if habit != nil { dangerZone }
                }
                .padding(Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .background(Theme.Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(habit == nil ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save", enabled: !name.isEmpty) {
                    Task { await save() }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.s)
                .bottomBar()
            }
        }
        .onAppear(perform: load)
        .alert("Alarm permission denied", isPresented: $alarmDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Saved as Standard. Enable alarms in Settings to switch back.")
        }
    }

    // MARK: Sections

    private var identity: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            FieldLabel(text: "Name")
            TextField("Check my posture", text: $name)
                .font(Theme.title(20))
                .padding(Theme.Space.m)
                .card()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 5), spacing: Theme.Space.s) {
                ForEach(Self.symbols, id: \.self) { candidate in
                    Button {
                        withAnimation(Theme.fast) { symbol = candidate }
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 16))
                            .foregroundStyle(symbol == candidate ? Color(hex: tintHex) : Theme.Palette.inkFaint)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(symbol == candidate ? Color(hex: tintHex).opacity(0.14) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Theme.Space.m) {
                ForEach(Self.tints, id: \.self) { candidate in
                    Button {
                        withAnimation(Theme.fast) { tintHex = candidate }
                    } label: {
                        Circle()
                            .fill(Color(hex: candidate))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: tintHex == candidate ? 3 : 0)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var nudgeCopy: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            FieldLabel(text: "Notification")
            TextField("Psst... check your posture :)", text: $nudgeText, axis: .vertical)
                .font(Theme.body(16))
                .lineLimit(1...3)
                .padding(Theme.Space.m)
                .card()
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            FieldLabel(text: "Intensity")
            ChipRow(
                options: Intensity.allCases,
                selection: $intensity,
                label: { $0.title },
                symbol: { $0.symbol }
            )
            Text(intensity.blurb)
                .font(Theme.footnote(13))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    private var cadence: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            FieldLabel(text: "Repeat")
            ChipRow(options: Mode.allCases, selection: $mode, label: { $0.label })

            switch mode {
            case .interval:
                stepperRow(
                    value: Schedule.duration(intervalMinutes),
                    decrement: { intervalMinutes = step(intervalMinutes, by: -1) },
                    increment: { intervalMinutes = step(intervalMinutes, by: 1) }
                )
            case .times:
                VStack(spacing: Theme.Space.s) {
                    stepperRow(
                        value: "\(perPeriodCount) time\(perPeriodCount == 1 ? "" : "s")",
                        decrement: { perPeriodCount = max(1, perPeriodCount - 1) },
                        increment: { perPeriodCount = min(24, perPeriodCount + 1) }
                    )
                    ChipRow(options: Period.allCases, selection: $period, label: { "per \($0.noun)" })
                }
            case .fixed:
                VStack(spacing: Theme.Space.s) {
                    ForEach(Array(fixedTimes.enumerated()), id: \.offset) { index, minute in
                        HStack {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { MinuteOfDay.date(minute) },
                                    set: { fixedTimes[index] = MinuteOfDay.minutes($0) }
                                ),
                                displayedComponents: [.hourAndMinute]
                            )
                            .labelsHidden()
                            Spacer()
                            if fixedTimes.count > 1 {
                                Button { fixedTimes.remove(at: index) } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.inkFaint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Space.m)
                        .card()
                    }
                    Button { fixedTimes.append(12 * 60) } label: {
                        Label("Add time", systemImage: "plus")
                            .font(Theme.caption(13))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            previewRow
        }
    }

    /// Concrete proof of what you just configured.
    private var previewRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            FieldLabel(text: preview.isEmpty ? "Never fires" : "Next")
            if preview.isEmpty {
                Text("Nothing fits these hours and days.")
                    .font(Theme.footnote(13))
                    .foregroundStyle(Theme.Palette.alarm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(preview, id: \.self) { date in
                            Text(Self.previewLabel(date))
                                .font(Theme.caption(12))
                                .foregroundStyle(Theme.Palette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(hex: tintHex).opacity(0.13)))
                        }
                    }
                }
            }
        }
        .animation(Theme.fast, value: preview)
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Only interval and per-period schedules need a window. For "At"
            // the times are the schedule, so the control would just imply a
            // constraint that does not exist.
            if mode != .fixed {
                FieldLabel(text: "Active hours")
                HStack(spacing: Theme.Space.m) {
                    timeBox("From", minute: $windowStart)
                    timeBox("Until", minute: $windowEnd)
                }
            }

            FieldLabel(text: "Days")
            HStack(spacing: Theme.Space.xs) {
                ForEach(1...7, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button {
                        withAnimation(Theme.fast) {
                            if on { weekdays.remove(day) } else { weekdays.insert(day) }
                        }
                    } label: {
                        Text(Self.dayLabel(day))
                            .font(Theme.caption(12))
                            .foregroundStyle(on ? .white : Theme.Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(on ? Color(hex: tintHex) : Theme.Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.Palette.hairline, lineWidth: on ? 0 : 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerZone: some View {
        Button(role: .destructive) {
            if let habit { context.delete(habit) }
            try? context.save()
            dismiss()
        } label: {
            Label("Delete", systemImage: "trash")
                .font(Theme.body(15))
                .foregroundStyle(Theme.Palette.alarm)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.m)
                .card()
        }
        .pressable()
    }

    // MARK: Pieces

    private func stepperRow(value: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack {
            Text(value).font(Theme.title(18)).foregroundStyle(Theme.Palette.ink)
            Spacer()
            HStack(spacing: Theme.Space.s) {
                circleButton("minus") { withAnimation(Theme.fast, decrement) }
                circleButton("plus") { withAnimation(Theme.fast, increment) }
            }
        }
        .padding(Theme.Space.m)
        .card()
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.Palette.canvas))
        }
        .buttonStyle(.plain)
    }

    private func timeBox(_ label: String, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption(12)).foregroundStyle(Theme.Palette.inkFaint)
            DatePicker(
                "",
                selection: Binding(
                    get: { MinuteOfDay.date(minute.wrappedValue) },
                    set: { minute.wrappedValue = MinuteOfDay.minutes($0) }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity)
        .card()
    }

    /// 1 minute steps up close, coarser once the gaps get long. Lets you dial
    /// in "every 2 minutes" for testing without 480 taps to reach 8 hours.
    private func step(_ minutes: Int, by direction: Int) -> Int {
        let size = switch minutes {
        case ..<15: 1
        case ..<60: 5
        case ..<180: 15
        default: 30
        }
        let adjusted = direction > 0 ? minutes + size : minutes - (minutes % size == 0 ? size : minutes % size)
        return min(max(adjusted, 1), 12 * 60)
    }

    /// "6 PM" today, "Mon 6 PM" beyond tomorrow.
    private static func previewLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "Tmrw \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    private static func dayLabel(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }

    /// Minimum gap between two nudges of this habit.
    ///
    /// Derived from the cadence you picked, at half the natural spacing. Two
    /// consequences, both intentional: the assistant can tighten a habit a
    /// little but never turn it into a per-minute nag, and nothing you set by
    /// hand is ever silently filtered out by its own floor.
    private var floor: Int {
        switch mode {
        case .interval:
            return max(1, intervalMinutes / 2)
        case .times:
            let span = max(windowEnd - windowStart, 1)
            let perDay = max(SchedulingService.dailyCount(
                count: perPeriodCount, period: period, schedule: builtWindow
            ), 1)
            let spacing = perDay > 1 ? span / (perDay - 1) : span
            return max(1, spacing / 2)
        case .fixed:
            return 1
        }
    }

    /// Window and weekdays only, for the floor calculation above.
    private var builtWindow: Schedule {
        Schedule(
            kind: .interval(minutes: 60),
            windowStartMinute: windowStart,
            windowEndMinute: windowEnd,
            weekdays: weekdays,
            minIntervalMinutes: 1
        )
    }

    /// The first few times this habit will actually fire, computed with the
    /// real scheduler.
    ///
    /// The horizon is a full week plus a day, not the scheduler's 48 hours.
    /// A Monday-only habit configured on a Saturday has no fire time inside
    /// two days, so the short horizon reported "nothing fits these hours and
    /// days" for a perfectly valid schedule.
    private var preview: [Date] {
        Array(SchedulingService.fireTimes(
            for: builtSchedule, from: .now, horizon: 8 * 24 * 3600
        ).prefix(6))
    }

    private var builtSchedule: Schedule {
        let kind: ScheduleKind = switch mode {
        case .interval: .interval(minutes: intervalMinutes)
        case .times: .spread(count: perPeriodCount, period: period)
        case .fixed: .fixedTimes(fixedTimes)
        }
        let fixed = mode == .fixed
        return Schedule(
            kind: kind,
            windowStartMinute: fixed ? 0 : windowStart,
            windowEndMinute: fixed ? 24 * 60 : windowEnd,
            weekdays: weekdays,
            minIntervalMinutes: floor
        )
    }

    private func load() {
        guard let habit else {
            nudgeText = "Psst... check your posture :)"
            return
        }
        name = habit.name
        nudgeText = habit.nudgeText
        intensity = habit.intensity
        symbol = habit.symbol
        tintHex = habit.tintHex
        let schedule = habit.schedule
        windowStart = schedule.windowStartMinute
        windowEnd = schedule.windowEndMinute
        weekdays = schedule.weekdays
        switch schedule.kind {
        case .interval(let minutes): mode = .interval; intervalMinutes = minutes
        case .spread(let count, let p): mode = .times; perPeriodCount = count; period = p
        case .fixedTimes(let times): mode = .fixed; fixedTimes = times
        }
    }

    private func save() async {
        var resolved = intensity
        if intensity == .alarm && AlarmService.authorization != .authorized {
            if case .success(false) = await AlarmService.requestAuthorization() {
                resolved = .standard
                alarmDenied = true
            } else if case .failure = await AlarmService.requestAuthorization() {
                resolved = .standard
                alarmDenied = true
            }
        }

        let copy = nudgeText.isEmpty ? "Psst... \(name.lowercased())" : nudgeText
        if let habit {
            habit.name = name
            habit.nudgeText = copy
            habit.intensity = resolved
            habit.schedule = builtSchedule
            habit.symbol = symbol
            habit.tintHex = tintHex
        } else {
            context.insert(Habit(
                name: name, nudgeText: copy, intensity: resolved,
                schedule: builtSchedule, symbol: symbol, tintHex: tintHex
            ))
        }
        try? context.save()
        await onSave()
        if !alarmDenied { dismiss() }
    }
}
