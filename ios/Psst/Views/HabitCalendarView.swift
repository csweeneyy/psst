import SwiftData
import SwiftUI

/// A month at a glance, and what actually happened on any given day.
struct HabitCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selected: Date?
    @State private var filter: UUID?

    private let calendar = Calendar.current

    private var scoped: [Habit] {
        filter == nil ? habits : habits.filter { $0.id == filter }
    }

    private var occurrences: [HabitOccurrence] { scoped.flatMap(\.occurrences) }

    /// Per-day tallies for the visible month.
    private var tallies: [Date: (completed: Int, answered: Int, scheduled: Int)] {
        var result: [Date: (Int, Int, Int)] = [:]
        for occurrence in occurrences {
            let day = calendar.startOfDay(for: occurrence.scheduledAt)
            guard calendar.isDate(day, equalTo: month, toGranularity: .month) else { continue }
            var bucket = result[day] ?? (0, 0, 0)
            bucket.2 += 1
            if occurrence.status != .pending { bucket.1 += 1 }
            if occurrence.status == .completed { bucket.0 += 1 }
            result[day] = bucket
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    filterRow
                    monthHeader
                    grid
                    legend
                    if let selected { dayDetail(selected) }
                    monthSummary
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.Palette.canvas)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
            }
        }
    }

    // MARK: Pieces

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                chip(title: "All", tint: Theme.Palette.ink, isOn: filter == nil) { filter = nil }
                ForEach(habits) { habit in
                    chip(
                        title: habit.name,
                        tint: HabitStyle.tint(habit.tintHex),
                        isOn: filter == habit.id
                    ) { filter = filter == habit.id ? nil : habit.id }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(
        title: String, tint: Color, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.footnote(14))
                .foregroundStyle(isOn ? Theme.Palette.onAccent : Theme.Palette.ink)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? tint : Theme.Palette.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)

            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(Theme.title(18))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()

            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Theme.Palette.ink)
    }

    private var grid: some View {
        let days = monthDays()
        return VStack(spacing: Theme.Space.s) {
            HStack(spacing: 4) {
                ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(Theme.Space.m)
        .card()
    }

    private func dayCell(_ day: Date) -> some View {
        let tally = tallies[day]
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)

        return Button {
            withAnimation(Theme.fast) {
                selected = isSelected ? nil : day
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(Theme.Palette.ink)
                Circle()
                    .fill(color(for: tally))
                    .frame(width: 6, height: 6)
                    .opacity(tally == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill(for: tally))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Palette.ink : (isToday ? Theme.Palette.inkFaint : .clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach([("All done", 1.0), ("Partial", 0.5), ("Missed", 0.0)], id: \.0) { label, rate in
                HStack(spacing: 5) {
                    Circle()
                        .fill(rate == 0 ? Theme.Palette.alarm : Theme.Palette.success.opacity(0.35 + 0.65 * rate))
                        .frame(width: 7, height: 7)
                    Text(label).font(Theme.caption(11)).foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func dayDetail(_ day: Date) -> some View {
        let items = occurrences
            .filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
            .sorted { $0.scheduledAt < $1.scheduledAt }

        VStack(alignment: .leading, spacing: Theme.Space.s) {
            FieldLabel(text: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            if items.isEmpty {
                Text("Nothing was scheduled.")
                    .font(Theme.footnote(14))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, occurrence in
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: occurrence.habit?.symbol ?? "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(HabitStyle.tint(occurrence.habit?.tintHex))
                                .frame(width: 24)
                            Text(occurrence.habit?.name ?? "Habit")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(occurrence.scheduledAt.formatted(date: .omitted, time: .shortened))
                                .font(Theme.footnote(13))
                                .foregroundStyle(Theme.Palette.inkSoft)
                            Image(systemName: occurrence.status.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(occurrence.status.accent)
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 10)
                        if index < items.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .card()
            }
        }
        .transition(.opacity)
    }

    private var monthSummary: some View {
        let entries = tallies.values
        let completed = entries.reduce(0) { $0 + $1.completed }
        let answered = entries.reduce(0) { $0 + $1.answered }
        let perfect = entries.filter { $0.answered > 0 && $0.completed == $0.answered }.count

        return HStack(spacing: 0) {
            summaryTile("\(completed)", "Done")
            Divider().frame(height: 30)
            summaryTile(answered == 0 ? "0%" : "\(Int(Double(completed) / Double(answered) * 100))%", "Rate")
            Divider().frame(height: 30)
            summaryTile("\(perfect)", "Clean days")
        }
        .padding(.vertical, Theme.Space.m)
        .card()
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.number(20)).foregroundStyle(Theme.Palette.ink)
            Text(label).font(Theme.caption(11)).foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private func shift(_ months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(Theme.fast) {
            month = moved
            selected = nil
        }
    }

    /// Leading nils pad the grid so the first of the month lands on its weekday.
    private func monthDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        let leading = calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: leading)
            + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func color(for tally: (completed: Int, answered: Int, scheduled: Int)?) -> Color {
        guard let tally, tally.answered > 0 else { return .clear }
        let rate = Double(tally.completed) / Double(tally.answered)
        return rate == 0 ? Theme.Palette.alarm : Theme.Palette.success.opacity(0.35 + 0.65 * rate)
    }

    private func fill(for tally: (completed: Int, answered: Int, scheduled: Int)?) -> Color {
        guard let tally, tally.answered > 0 else { return Theme.Palette.surface }
        let rate = Double(tally.completed) / Double(tally.answered)
        return rate == 0
            ? Theme.Palette.alarm.opacity(0.10)
            : Theme.Palette.success.opacity(0.06 + 0.16 * rate)
    }

}
