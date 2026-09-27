import SwiftData
import SwiftUI

/// Tab one. What is due, with the assistant a tap away on the same surface.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(NudgeCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \HabitOccurrence.scheduledAt) private var occurrences: [HabitOccurrence]
    @Query private var habits: [Habit]

    @State private var rescheduling: HabitOccurrence?
    @State private var firing: HabitOccurrence?
    @State private var pendingDelete: HabitOccurrence?
    @State private var clock = Date.now

    /// Anything pending whose moment has arrived. These do not belong in
    /// "Up next", which is a list of things that have not happened yet.
    private var overdue: [HabitOccurrence] {
        occurrences.filter {
            $0.habit != nil && $0.status == .pending && $0.scheduledAt <= clock
        }
    }

    private var upNext: [HabitOccurrence] {
        occurrences.filter {
            $0.habit != nil && $0.status == .pending && $0.scheduledAt > clock
                && Calendar.current.isDateInToday($0.scheduledAt)
        }
    }

    private var logged: [HabitOccurrence] {
        occurrences
            .filter {
                $0.habit != nil && $0.status != .pending
                    && Calendar.current.isDateInToday($0.scheduledAt)
            }
            .sorted { ($0.respondedAt ?? $0.scheduledAt) > ($1.respondedAt ?? $1.scheduledAt) }
    }

    var body: some View {
        NavigationStack {
            // A real `List`, not a hand-rolled ScrollView of cards.
            //
            // `swipeActions` is the platform's own gesture arbitration against
            // the scroll view, which a custom `DragGesture` cannot reliably win.
            // It also brings row reuse, so long histories stay smooth, and the
            // inset-grouped style is exactly the look this screen was imitating
            // by hand.
            List {
                crest
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if !overdue.isEmpty {
                    Section("Now") { rows(overdue, dismissable: true) }
                }
                if !upNext.isEmpty {
                    Section("Up next") { rows(upNext, dismissable: true) }
                }
                if !logged.isEmpty {
                    Section("Logged") { rows(logged, dismissable: true) }
                }
                if let problem = coordinator.lastError {
                    // An empty list and a failed load look identical, and one
                    // of them is alarming. Say which it is.
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.footnote(14))
                        .foregroundStyle(Theme.Palette.warning)
                        .listRowBackground(Theme.Palette.surface)
                } else if habits.isEmpty {
                    EmptyStateView(
                        symbol: "bell.slash",
                        title: "No habits yet",
                        message: "Add one on the Habits tab."
                    )
                    .listRowBackground(Color.clear)
                } else if overdue.isEmpty && upNext.isEmpty && logged.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.circle",
                        title: "Nothing due today",
                        message: nextUpMessage
                    )
                    .listRowBackground(Color.clear)
                }

                budget
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Today")
            .navigationSubtitle(Text(clock.formatted(.dateTime.weekday(.wide).month(.wide).day())))
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                // An empty navigation bar row above a large title reads as
                // dead space. The counter earns it and is useful at a glance.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 11))
                        Text("\(PointsService.today(habits))")
                            .font(Theme.caption(14).monospacedDigit())
                    }
                    .foregroundStyle(Theme.Palette.ink)
                }
            }
        }
        .sheet(item: $rescheduling) { occurrence in
            RescheduleSheet(occurrence: occurrence) { move(occurrence, to: $0) }
        }
        // `alert`, not `confirmationDialog`. The latter renders as an action
        // sheet anchored to the bottom of the screen regardless of which row
        // you swiped, which reads as misplaced. Notes uses a centred alert.
        .alert(
            "Delete this reminder?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { occurrence in
            Button("Delete", role: .destructive) {
                dismiss(occurrence)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { occurrence in
            Text(occurrence.habit?.name ?? "This reminder")
        }
        .fullScreenCover(item: $firing) { occurrence in
            NudgeTakeover(occurrence: occurrence) { status in
                resolve(occurrence, status)
            }
        }
        .task { await tick() }
        .onChange(of: scenePhase) { _, phase in
            // Returning from the Lock Screen: re-read before deciding whether
            // anything is still owed.
            guard phase == .active else { return }
            clock = .now
            if let showing = firing, showing.status != .pending { firing = nil }
            Task { await coordinator.resync(context: context) }
        }
    }

    /// The bird, the level, and how far through it you are.
    ///
    /// Sits above the list rather than in the navigation bar so it has room to
    /// mean something. It reacts to state you caused: upright on a streak,
    /// slumped after a recent miss, beak open when something is due right now.
    private var crest: some View {
        let earned = PointsService.allTime(habits)
        let level = Level.current(for: earned)
        let progress = Level.progress(for: earned)

        return HStack(spacing: Theme.Space.m) {
            MascotView(
                mood: MascotMood.current(habits: habits, occurrences: occurrences, now: clock),
                size: 46
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(level.name)
                        .font(Theme.title(17))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("\(earned)")
                        .font(Theme.caption(13).monospacedDigit())
                        .foregroundStyle(Theme.Palette.inkSoft)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.well)
                        Capsule()
                            .fill(Theme.Palette.ink)
                            .frame(width: max(geometry.size.width * progress, progress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 5)

                if let remaining = Level.pointsToNext(from: earned),
                   let next = Level.next(after: level) {
                    Text("\(remaining) to \(next.name)")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(Theme.motion, value: earned)
    }

    @ViewBuilder
    private func rows(_ items: [HabitOccurrence], dismissable: Bool) -> some View {
        ForEach(items) { occurrence in
            OccurrenceRow(
                occurrence: occurrence,
                onResolve: resolve,
                onReschedule: occurrence.status == .pending ? { rescheduling = $0 } : nil
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Theme.Palette.surface)
            .accessibilityIdentifier("row.\(occurrence.id.uuidString)")
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if dismissable {
                    // Not `role: .destructive`. That role makes SwiftUI animate
                    // the row out the instant the swipe completes, so the row
                    // vanished and then sprang back when the confirmation
                    // appeared. A plain red button leaves the row in place
                    // until the user actually confirms.
                    Button { pendingDelete = occurrence } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(Theme.Palette.alarm)
                }
            }
        }
    }

    /// Today's tally, shown in the navigation bar.
    private var progressLabel: String {
        let today = occurrences.filter {
            $0.habit != nil && Calendar.current.isDateInToday($0.scheduledAt)
        }
        let answered = today.filter { $0.status != .pending }
        let done = answered.filter { $0.status == .completed }.count
        guard !today.isEmpty else { return "nothing today" }
        return "\(done) of \(today.count) done"
    }

    /// Names the next nudge and which habit owns it. Without this, a habit
    /// whose active window has already passed looks like a broken app rather
    /// than a schedule working as configured.
    private var nextUpMessage: String? {
        let inputs = habits.map {
            HabitPlanInput(id: $0.id, schedule: $0.schedule, intensity: $0.intensity, isPaused: $0.isPaused)
        }
        guard let next = SchedulingService.nextFireTime(habits: inputs, from: clock),
              let habit = habits.first(where: { $0.id == next.habitID }) else {
            return "No habit fits its own hours and days. Check their schedules."
        }
        let when = Calendar.current.isDateInTomorrow(next.date)
            ? "tomorrow at \(next.date.formatted(date: .omitted, time: .shortened))"
            : next.date.formatted(.dateTime.weekday(.wide).hour().minute())
        return "Next up: \(habit.name) \(when)."
    }

    /// What the app currently has booked with iOS.
    ///
    /// Surfaced rather than hidden because the notification slot count is a
    /// hard system limit: at 64 of 64, the next habit you add silently gets
    /// nothing, and there is no other way to find that out.
    private var budget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scheduled with iOS")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.Palette.inkFaint)
            HStack(spacing: Theme.Space.m) {
                pill(progressLabel, "checkmark.circle", Theme.Palette.inkFaint)
                pill(
                    "\(coordinator.scheduledNotifications) of 64 reminders",
                    "bell",
                    coordinator.scheduledNotifications >= 60
                        ? Theme.Palette.warning : Theme.Palette.inkFaint
                )
                if coordinator.scheduledLiveActivities > 0 {
                    pill("\(coordinator.scheduledLiveActivities) Lock Screen", "rectangle.on.rectangle", Theme.Palette.inkFaint)
                }
                if coordinator.scheduledAlarms > 0 {
                    pill("\(coordinator.scheduledAlarms) alarm\(coordinator.scheduledAlarms == 1 ? "" : "s")", "alarm", Theme.Palette.inkFaint)
                }
                Spacer()
            }
            if coordinator.scheduledNotifications >= 60 {
                Text("Near the system limit. Some reminders may be dropped.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func pill(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(text).font(Theme.caption(11))
        }
        .foregroundStyle(color)
    }

    // MARK: Actions

    /// Drives the overdue split and raises the in-app takeover. A nudge that
    /// comes due while the app is open never fires a notification, so without
    /// this it would silently pass.
    private func tick() async {
        while !Task.isCancelled {
            clock = .now

            // An occurrence answered elsewhere, typically from the Lock Screen,
            // must not keep the takeover on screen.
            if let showing = firing, showing.status != .pending {
                firing = nil
            }

            if firing == nil, rescheduling == nil,
               let due = overdue.first(where: { $0.scheduledAt > clock.addingTimeInterval(-600) }) {
                firing = due
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func move(_ occurrence: HabitOccurrence, to newTime: Date) {
        occurrence.scheduledAt = newTime
        occurrence.isPinned = true
        occurrence.deliveryScheduled = true
        try? context.save()

        let id = occurrence.id
        let habit = occurrence.habit
        Task {
            // Put the alert on the schedule before the slow part. Moving a
            // nudge and immediately locking the phone used to lose it: the
            // resync had not finished when iOS suspended the app.
            if let habit {
                await NudgeDelivery.deliver(habit: habit, occurrenceID: id, at: newTime)
            }
            await coordinator.resync(context: context)
        }
    }

    private func dismiss(_ occurrence: HabitOccurrence) {
        let id = occurrence.id
        withAnimation(Theme.motion) { context.delete(occurrence) }
        try? context.save()
        Task {
            await NudgeActivity.resolve(occurrenceID: id)
            await coordinator.resync(context: context)
        }
    }

    private func resolve(_ occurrence: HabitOccurrence, _ status: OccurrenceStatus) {
        let id = occurrence.id
        let wasShowing = firing?.id == id

        if status == .skipped {
            // Later means later, not cancelled.
            withAnimation(Theme.motion) { if wasShowing { firing = nil } }
            Task {
                await NudgeActivity.resolve(
                    occurrenceID: id,
                    snoozedUntil: .now.addingTimeInterval(TimeInterval(FollowUp.delayMinutes * 60))
                )
                await FollowUp.snooze(occurrenceID: id)
                await chain(after: id, wasShowing: wasShowing)
                await coordinator.resync(context: context)
            }
            return
        }

        withAnimation(Theme.motion) {
            occurrence.status = status
            occurrence.respondedAt = .now
            if wasShowing { firing = nil }
        }
        try? context.save()
        Task {
            await NudgeActivity.resolve(occurrenceID: id)
            await chain(after: id, wasShowing: wasShowing)
            await coordinator.resync(context: context)
        }
    }

    /// With the app open no notification fires, so a queued nudge would sit
    /// unseen until the next tick. Raise its takeover straight away instead.
    private func chain(after id: UUID, wasShowing: Bool) async {
        guard let followerID = await NudgeQueue.advance(after: id), wasShowing else { return }
        // A beat, so one card does not appear to morph into the next.
        try? await Task.sleep(for: .milliseconds(320))
        guard let follower = occurrences.first(where: { $0.id == followerID }) else { return }
        clock = .now
        withAnimation(Theme.motion) { firing = follower }
    }
}

// MARK: - Row

struct OccurrenceRow: View {
    let occurrence: HabitOccurrence
    let onResolve: (HabitOccurrence, OccurrenceStatus) -> Void
    var onReschedule: ((HabitOccurrence) -> Void)?

    private var habit: Habit? { occurrence.habit }
    private var tint: Color { HabitStyle.tint(habit?.tintHex) }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: habit?.symbol ?? "circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(habit?.name ?? "Habit")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.Palette.ink)
                timeLabel
            }

            Spacer(minLength: Theme.Space.s)

            if occurrence.status == .pending {
                HStack(spacing: Theme.Space.s) {
                    circle("xmark", Theme.Palette.inkFaint, Theme.Palette.well) {
                        onResolve(occurrence, .skipped)
                    }
                    circle("checkmark", Theme.Palette.onAccent, Theme.Palette.accent) {
                        onResolve(occurrence, .completed)
                    }
                }
            } else {
                Image(systemName: occurrence.status.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(occurrence.status.accent)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var timeLabel: some View {
        let text = occurrence.scheduledAt.formatted(date: .omitted, time: .shortened)
        if let onReschedule {
            Button { onReschedule(occurrence) } label: {
                HStack(spacing: 3) {
                    Text(text)
                    if occurrence.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                    }
                }
                .font(Theme.footnote(13))
                .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.borderless)
        } else {
            Text(text).font(Theme.footnote(13)).foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    private func circle(
        _ symbol: String, _ fg: Color, _ bg: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: 32, height: 32)
                .background(Circle().fill(bg))
        }
        // `.borderless`, not `.plain`. Inside a `List` row, a plain button
        // makes UIKit delay the pan recogniser while it decides whether the
        // touch belongs to the control, which is what made the swipe feel
        // like it needed force and sometimes stall halfway.
        .buttonStyle(.borderless)
    }

}

// MARK: - In-app takeover

/// When a nudge comes due with the app open, no notification fires. This takes
/// the screen instead, so an open app is never a way to dodge a reminder.
struct NudgeTakeover: View {
    let occurrence: HabitOccurrence
    let onResolve: (OccurrenceStatus) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private var habit: Habit? { occurrence.habit }
    private var tint: Color { HabitStyle.tint(habit?.tintHex) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Prompt fills the upper half rather than floating in the
                // middle of a blank screen.
                VStack(spacing: Theme.Space.l) {
                    Spacer()
                    Image(systemName: habit?.symbol ?? "bell")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(tint)
                        .frame(width: 124, height: 124)
                        .background(Circle().fill(tint.opacity(0.14)))
                        .scaleEffect(appeared ? 1 : 0.8)

                    Text(habit?.nudgeText ?? "Time for it")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(Theme.displayTracking)
                        .foregroundStyle(Theme.Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.xl)

                    Text(occurrence.scheduledAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                // Targets sized so they are unmissable without looking, which
                // is the whole point of a takeover.
                VStack(spacing: Theme.Space.m) {
                    bigButton(
                        "Done",
                        symbol: "checkmark",
                        foreground: Theme.Palette.onAccent,
                        background: Theme.Palette.accent,
                        height: max(96, geometry.size.height * 0.13)
                    ) {
                        onResolve(.completed)
                        dismiss()
                    }

                    bigButton(
                        "Later",
                        symbol: "clock",
                        foreground: Theme.Palette.ink,
                        background: Theme.Palette.surface,
                        height: max(76, geometry.size.height * 0.10)
                    ) {
                        onResolve(.skipped)
                        dismiss()
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.canvas)
        .onAppear { withAnimation(Theme.motion) { appeared = true } }
    }

    private func bigButton(
        _ title: String,
        symbol: String,
        foreground: Color,
        background: Color,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Text(title).font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .pressable()
    }
}

// MARK: - Reschedule

/// Moves one nudge to an exact minute.
struct RescheduleSheet: View {
    let occurrence: HabitOccurrence
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                HStack(spacing: Theme.Space.s) {
                    ForEach([1, 2, 5, 15], id: \.self) { minutes in
                        Button {
                            time = Date.now.addingTimeInterval(Double(minutes) * 60)
                        } label: {
                            Text("+\(minutes)m")
                                .font(Theme.footnote(14))
                                .foregroundStyle(Theme.Palette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                        .fill(Theme.Palette.surface)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                PrimaryButton(title: "Move") {
                    onSave(time)
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.l)
            .background(Theme.Palette.canvas)
            .navigationTitle(occurrence.habit?.name ?? "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .onAppear { time = occurrence.scheduledAt }
    }
}
