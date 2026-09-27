import Charts
import SwiftData
import SwiftUI

/// Everything known about one habit, and the one change worth making to it.
struct HabitDetailView: View {
    let habit: Habit
    let onChange: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    private var tint: Color { Color(hex: habit.tintHex) }
    private var occurrences: [HabitOccurrence] { habit.occurrences }

    private var week: HabitStats { HabitStatsService.stats(for: occurrences, days: 7) }
    private var month: HabitStats { HabitStatsService.stats(for: occurrences, days: 30) }
    private var hours: [HourSlice] { HabitStatsService.hourly(for: occurrences) }
    private var days: [DaySlice] { HabitStatsService.daily(for: occurrences, days: 14) }

    private var suggestion: ScheduleSuggestion? {
        ScheduleAdvisor.suggestion(
            schedule: habit.schedule, intensity: habit.intensity, occurrences: occurrences
        )
    }

    var body: some View {
        NavigationStack {
            List {
                hero
                if let suggestion { suggestionSection(suggestion) }
                numbers
                recent
                timeOfDay
                notesSection
                actions
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { save(); dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }.foregroundStyle(Theme.Palette.ink)
                }
            }
        }
        .sheet(isPresented: $editing) {
            HabitSetupView(habit: habit) { await onChange() }
        }
        .alert("Delete this habit?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                context.delete(habit)
                try? context.save()
                dismiss()
                Task { await onChange() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(habit.name) and its history will be removed.")
        }
        .onAppear { notes = habit.notes }
        .onDisappear { save() }
    }

    // MARK: Sections

    private var hero: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: habit.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(tint.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.schedule.summary)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.Palette.ink)
                        HStack(spacing: 5) {
                            Image(systemName: habit.intensity.symbol).font(.system(size: 10))
                            Text(habit.intensity.title)
                            if habit.isPaused {
                                Text("· Paused")
                            }
                        }
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }

                Text(habit.nudgeText)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Palette.well)
                    )
            }
            .padding(.vertical, Theme.Space.xs)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    private func suggestionSection(_ suggestion: ScheduleSuggestion) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label("Suggestion", systemImage: "sparkles")
                    .font(Theme.caption(12))
                    .foregroundStyle(tint)
                Text(suggestion.rationale)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button { apply(suggestion) } label: {
                    Text(suggestion.actionTitle)
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Theme.Palette.accent)
                        )
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, Theme.Space.xs)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    private var numbers: some View {
        Section {
            HStack(spacing: 0) {
                stat("\(HabitStatsService.streak(for: occurrences))", "Streak")
                divider
                stat("\(HabitStatsService.longestStreak(for: occurrences))", "Best")
                divider
                stat("\(Int(week.completionRate * 100))%", "7 days")
                divider
                stat("\(HabitStatsService.daysActive(since: habit.createdAt))", "Days in")
            }
            .padding(.vertical, Theme.Space.s)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Theme.Palette.surface)
        } footer: {
            Text("\(month.completed) of \(month.total) answered in the last 30 days.")
        }
    }

    private var recent: some View {
        Section("Last 14 days") {
            HStack(spacing: 5) {
                ForEach(days) { day in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: day))
                            .frame(height: 30)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.inkFaint)
                    }
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    @ViewBuilder
    private var timeOfDay: some View {
        let live = hours.filter(\.hasData)
        if !live.isEmpty {
            Section("When you answer") {
                Chart(live) { slice in
                    BarMark(
                        x: .value("Hour", slice.hour),
                        y: .value("Answered", slice.rate)
                    )
                    .foregroundStyle(tint.opacity(0.25 + 0.75 * slice.rate))
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let rate = value.as(Double.self) {
                                Text("\(Int(rate * 100))%")
                            }
                        }
                    }
                }
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(Schedule.clock(hour * 60))
                            }
                        }
                    }
                }
                .frame(height: 130)
                .padding(.vertical, Theme.Space.s)
                .listRowBackground(Theme.Palette.surface)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField(
                "Why this matters, what counts as done",
                text: $notes,
                axis: .vertical
            )
            .font(Theme.body(16))
            .lineLimit(2...8)
            .focused($notesFocused)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    private var actions: some View {
        Section {
            Button {
                habit.isPaused.toggle()
                try? context.save()
                Task { await onChange() }
            } label: {
                Label(
                    habit.isPaused ? "Resume" : "Pause",
                    systemImage: habit.isPaused ? "play.circle" : "pause.circle"
                )
                .foregroundStyle(Theme.Palette.ink)
            }
            .buttonStyle(.borderless)
            .listRowBackground(Theme.Palette.surface)

            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete habit", systemImage: "trash")
                    .foregroundStyle(Theme.Palette.alarm)
            }
            .buttonStyle(.borderless)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    // MARK: Pieces

    private var divider: some View {
        Divider().frame(height: 28)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.number(20)).foregroundStyle(Theme.Palette.ink)
            Text(label).font(Theme.caption(11)).foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    /// Grey for a day with nothing scheduled, so an empty day is visibly
    /// different from a failed one.
    private func color(for day: DaySlice) -> Color {
        if day.scheduled == 0 { return Theme.Palette.well }
        if day.answered == 0 { return Theme.Palette.well }
        if day.rate >= 0.999 { return tint }
        if day.rate <= 0.001 { return Theme.Palette.alarm.opacity(0.35) }
        return tint.opacity(0.25 + 0.6 * day.rate)
    }

    private func save() {
        guard habit.notes != notes else { return }
        habit.notes = notes
        try? context.save()
    }

    private func apply(_ suggestion: ScheduleSuggestion) {
        withAnimation(Theme.motion) {
            if case .raiseIntensity(let intensity) = suggestion.kind {
                habit.intensity = intensity
            } else {
                habit.schedule = suggestion.applied(to: habit.schedule)
            }
        }
        try? context.save()
        Task { await onChange() }
    }
}
