import SwiftData
import SwiftUI

/// Sunday evening: what actually stuck.
struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var habits: [Habit]

    private var review: WeeklyReview { WeeklyReviewService.build(habits: habits) }

    var body: some View {
        NavigationStack {
            List {
                headline
                if let best = review.bestDay { bestDay(best) }
                habitBreakdown
                if !notes.isEmpty { takeaways }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
            }
        }
    }

    private var headline: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("\(Int(review.rate * 100))%")
                        .font(.system(size: 44, weight: .bold))
                        .tracking(Theme.displayTracking)
                        .foregroundStyle(Theme.Palette.ink)
                    if abs(review.delta) >= 0.01 {
                        Label(
                            "\(Int(abs(review.delta) * 100))%",
                            systemImage: review.delta > 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(Theme.caption(13))
                        .foregroundStyle(review.delta > 0 ? Theme.Palette.success : Theme.Palette.alarm)
                    }
                }
                Text("\(review.completed) of \(review.answered) nudges answered this week.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.vertical, Theme.Space.xs)
            .listRowBackground(Theme.Palette.surface)
        }
    }

    private func bestDay(_ best: (date: Date, completed: Int)) -> some View {
        Section {
            HStack {
                Label(best.date.formatted(.dateTime.weekday(.wide)), systemImage: "star")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(best.completed) done")
                    .font(Theme.footnote(14).monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .listRowBackground(Theme.Palette.surface)
        } header: {
            Text("Best day")
        }
    }

    private var habitBreakdown: some View {
        Section("By habit") {
            ForEach(review.lines) { line in
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: line.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: line.tintHex))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(hex: line.tintHex).opacity(0.12)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name).font(Theme.body(16)).foregroundStyle(Theme.Palette.ink)
                        Text(
                            line.answered == 0
                                ? "Nothing scheduled"
                                : "\(line.completed) of \(line.answered)\(line.streak > 0 ? " · \(line.streak) day streak" : "")"
                        )
                        .font(Theme.footnote(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Spacer(minLength: Theme.Space.s)

                    if line.answered > 0 {
                        Text("\(Int(line.rate * 100))%")
                            .font(Theme.footnote(15).monospacedDigit())
                            .foregroundStyle(
                                line.rate >= 0.7 ? Theme.Palette.success
                                    : line.rate < 0.4 ? Theme.Palette.alarm : Theme.Palette.inkSoft
                            )
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
        }
    }

    private var notes: [WeeklyReview.HabitLine] {
        review.lines.filter { $0.suggestion != nil }
    }

    private var takeaways: some View {
        Section {
            ForEach(notes) { line in
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name).font(Theme.caption(12)).foregroundStyle(Theme.Palette.inkFaint)
                    Text(line.suggestion ?? "")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .listRowBackground(Theme.Palette.surface)
            }
        } header: {
            Text("Worth changing")
        } footer: {
            Text("Open a habit to apply any of these.")
        }
    }
}
