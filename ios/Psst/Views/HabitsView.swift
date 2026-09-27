import SwiftData
import SwiftUI

/// Tab two. Aggregation first, setup behind the button.
struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NudgeCoordinator.self) private var coordinator

    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var editing: Habit?
    @State private var viewing: Habit?
    @State private var creating = false
    @State private var pendingDelete: Habit?
    @State private var reviewing = false
    @State private var calendaring = false

    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty {
                    EmptyStateView(symbol: "plus.circle", title: "No habits yet")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        overview
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Theme.Palette.surface)
                    }
                    Section {
                        ForEach(habits) { habit in
                            Button { viewing = habit } label: { HabitRow(habit: habit) }
                                .buttonStyle(.borderless)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Theme.Palette.surface)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    // Plain button, not `role: .destructive`:
                                    // the role animates the row out before the
                                    // confirmation has been answered.
                                    Button { pendingDelete = habit } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(Theme.Palette.alarm)
                                }
                                .contextMenu {
                                    Button { viewing = habit } label: {
                                        Label("Insights", systemImage: "chart.bar")
                                    }
                                    Button { editing = habit } label: {
                                        Label("Edit", systemImage: "slider.horizontal.3")
                                    }
                                    Button {
                                        habit.isPaused.toggle()
                                        try? context.save()
                                        Task { await coordinator.resync(context: context) }
                                    } label: {
                                        Label(
                                            habit.isPaused ? "Resume" : "Pause",
                                            systemImage: habit.isPaused ? "play" : "pause"
                                        )
                                    }
                                    Button(role: .destructive) { pendingDelete = habit } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Habits")
            .toolbarBackground(Theme.Palette.canvas, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .accessibilityLabel("Add habit")
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !habits.isEmpty {
                        Button { calendaring = true } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                        }
                        .accessibilityLabel("Calendar")
                        Button { reviewing = true } label: {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                        }
                        .accessibilityLabel("Weekly review")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "New habit", symbol: "plus") { creating = true }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.s)
                    .bottomBar()
            }
        }
        .sheet(isPresented: $creating) {
            HabitSetupView(habit: nil) { await coordinator.resync(context: context) }
        }
        .sheet(item: $editing) { habit in
            HabitSetupView(habit: habit) { await coordinator.resync(context: context) }
        }
        .sheet(isPresented: $reviewing) { WeeklyReviewView() }
        .sheet(isPresented: $calendaring) { HabitCalendarView() }
        .sheet(item: $viewing) { habit in
            HabitDetailView(habit: habit) { await coordinator.resync(context: context) }
        }
        .alert(
            "Delete this habit?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { habit in
            Button("Delete", role: .destructive) { delete(habit) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { habit in
            Text("\(habit.name) and its history will be removed.")
        }
    }

    private func delete(_ habit: Habit) {
        withAnimation(Theme.motion) { context.delete(habit) }
        try? context.save()
        pendingDelete = nil
        Task { await coordinator.resync(context: context) }
    }

    private var overview: some View {
        let week = HabitStatsService.stats(for: habits.flatMap(\.occurrences), days: 7)
        return HStack(spacing: 0) {
            tile("\(Int(week.completionRate * 100))%", "7 days")
            Divider().frame(height: 34)
            tile("\(week.completed)", "Done")
            Divider().frame(height: 34)
            tile("\(habits.filter { !$0.isPaused }.count)", "Active")
        }
        .padding(.vertical, Theme.Space.m)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.number(22)).foregroundStyle(Theme.Palette.ink)
            Text(label).font(Theme.caption(12)).foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HabitRow: View {
    let habit: Habit

    private var tint: Color { Color(hex: habit.tintHex) }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: habit.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(habit.name).font(Theme.body(16)).foregroundStyle(Theme.Palette.ink)
                    if habit.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.inkFaint)
                    }
                }
                Text(habit.schedule.summary)
                    .font(Theme.footnote(13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.s)

            let stats = HabitStatsService.stats(for: habit.occurrences, days: 7)
            Text("\(Int(stats.completionRate * 100))%")
                .font(Theme.footnote(14).monospacedDigit())
                .foregroundStyle(Theme.Palette.inkSoft)

            Image(systemName: habit.intensity.symbol)
                .font(.system(size: 12))
                .foregroundStyle(intensityColor)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkFaint)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.Palette.surface)
        .contentShape(Rectangle())
        .opacity(habit.isPaused ? 0.5 : 1)
    }

    private var intensityColor: Color {
        switch habit.intensity {
        case .gentle: Theme.Palette.inkFaint
        case .standard: Theme.Palette.inkSoft
        case .alarm: Theme.Palette.alarm
        }
    }
}
