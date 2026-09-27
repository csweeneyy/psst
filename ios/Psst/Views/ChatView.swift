import SwiftData
import SwiftUI
import UIKit

/// The assistant.
///
/// Opens empty every time. Past turns are still written to the store and are
/// still sent to the model as context, but a conversation you finished
/// yesterday is not what you want to look at when you open this to say one
/// thing. The transcript is working memory, not a history feature.
struct ChatView: View {
    /// `true` when shown as a tab rather than a sheet: no close button, and
    /// the page owns its own safe area.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NudgeCoordinator.self) private var coordinator

    @Query private var habits: [Habit]

    @State private var turns: [Bubble] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var speech = SpeechService()
    /// Text already in the field when dictation started, so speaking appends
    /// rather than wiping what you typed.
    @State private var dictationBase = ""
    @State private var failure: String?
    @State private var showHistory = false
    @State private var awaitingConfirmation: PendingChange?
    @FocusState private var focused: Bool

    /// A reply whose changes have not been applied yet because at least one
    /// of them destroys something.
    struct PendingChange: Identifiable {
        let id = UUID()
        let reply: String
        let mutations: [Mutation]
        let summary: String
    }

    struct Bubble: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        let text: String
        var applied: String?
        var warning: String?
    }

    var body: some View {
        // As a tab this has to be a real navigation stack, not a hand-rolled
        // header. A `Text` styled to look like a large title is never quite
        // the same size or at the same height as the genuine article, which is
        // why this page sat higher and in a smaller font than Home and Habits.
        Group {
            if embedded {
                NavigationStack {
                    transcript
                        .background(Theme.Palette.canvas)
                        .navigationTitle("Psst")
                        .toolbarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showHistory = true } label: {
                                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                        .foregroundStyle(Theme.Palette.ink)
                                }
                                .accessibilityLabel("Past conversations")
                            }
                        }
                }
            } else {
                VStack(spacing: 0) {
                    header
                    transcript
                }
            }
        }
        .background(Theme.Palette.canvas)
        .sheet(isPresented: $showHistory) { ChatHistoryView() }
        // `safeAreaInset` is what makes the composer track the keyboard
        // correctly. As a plain sibling in a VStack it kept its original
        // height when the keyboard grew, which is how the emoji keyboard
        // ended up covering the field.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let failure {
                    Text(failure)
                        .font(Theme.footnote(13))
                        .foregroundStyle(Theme.Palette.alarm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.bottom, Theme.Space.xs)
                }
                composer
            }
            .background(Theme.Palette.canvas)
        }
        .presentationDragIndicator(.hidden)
        // Raised on arrival either way. Chat is the leftmost tab, so you only
        // land here deliberately, and the whole point is to say one thing fast.
        .onAppear { focused = true }
        .alert(
            "Confirm",
            isPresented: Binding(
                get: { awaitingConfirmation != nil },
                set: { if !$0 { awaitingConfirmation = nil } }
            ),
            presenting: awaitingConfirmation
        ) { pending in
            Button("Delete", role: .destructive) { confirm(pending) }
            Button("Cancel", role: .cancel) {
                turns.append(Bubble(isUser: false, text: "Cancelled, nothing was changed."))
                awaitingConfirmation = nil
            }
        } message: { pending in
            Text(pending.summary)
        }
    }

    private func confirm(_ pending: PendingChange) {
        let summary = MutationApplier.apply(pending.mutations, habits: habits, context: context)
        context.insert(ChatMessage(role: "assistant", text: pending.reply, appliedSummary: summary))
        try? context.save()
        withAnimation(Theme.fast) {
            turns.append(Bubble(isUser: false, text: pending.reply, applied: summary))
        }
        awaitingConfirmation = nil
        Task { await coordinator.resync(context: context) }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            Text("Psst")
                .font(embedded ? Theme.largeTitle(32) : Theme.title(17))
                .displayTracking()
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            // The transcript starts empty every time, so history needs a door.
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .buttonStyle(.plain)
            if !embedded {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    @ViewBuilder
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                    if turns.isEmpty { opener }
                    ForEach(turns) { turn in
                        MessageBubble(bubble: turn).id(turn.id)
                    }
                    if sending {
                        TypingIndicator().id("typing")
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in
                withAnimation(Theme.fast) { proxy.scrollTo(turns.last?.id, anchor: .bottom) }
            }
        }
    }

    /// What you see before you have said anything.
    ///
    /// Removed the prefilled example pills because they were not helpful, and
    /// left a blank screen behind. This says what the assistant can actually
    /// see, which is both reassuring and the answer to "what can I ask it".
    private var opener: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            MascotView(mood: .calm, size: 52)

            Text("Ask me anything about your habits.")
                .font(Theme.title(20))
                .foregroundStyle(Theme.Palette.ink)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(contextLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark")
                        .font(Theme.footnote(14))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }

            Text("I can change schedules, log a past day, clear history, and answer questions about any date you have data for.")
                .font(Theme.footnote(14))
                .foregroundStyle(Theme.Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    private var contextLines: [String] {
        let occurrences = habits.flatMap(\.occurrences)
        let earliest = occurrences.map(\.scheduledAt).min()
        var lines = ["\(habits.count) habit\(habits.count == 1 ? "" : "s")"]
        if !occurrences.isEmpty {
            lines.append("\(occurrences.count) logged nudges")
        }
        if let earliest {
            let days = Calendar.current.dateComponents([.day], from: earliest, to: .now).day ?? 0
            if days > 0 { lines.append("history back to \(earliest.formatted(.dateTime.month(.abbreviated).day()))") }
        }
        return lines
    }

    /// The composer.
    ///
    /// One capsule with one button on its right, which is the mic until you
    /// have typed something and the send once you have. Dictation replaces the
    /// field with a live waveform driven by real microphone loudness rather
    /// than an animation, and the words appear above it as they are heard, so
    /// you can see it working without watching a text field twitch.
    private var composer: some View {
        VStack(spacing: 8) {
            if speech.isRecording, !liveText.isEmpty {
                Text(liveText)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                Group {
                    if speech.isRecording {
                        waveform
                    } else {
                        TextField("Message", text: $draft, axis: .vertical)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.Palette.ink)
                            .tint(Theme.Palette.ink)
                            .focused($focused)
                            .lineLimit(1...5)
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, 9)
                    }
                }
                .frame(minHeight: 38)
                .background(Capsule().fill(Theme.Palette.surface))
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))

                composerButton
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.Palette.canvas)
        .animation(Theme.fast, value: speech.isRecording)
        .animation(Theme.fast, value: canSend)
    }

    /// Live microphone loudness. Bars are seeded at a hairline so an empty
    /// waveform still reads as a waveform rather than a blank pill.
    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(speech.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.Palette.ink)
                    .frame(width: 3, height: max(CGFloat(level) * 22, 3))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .animation(.linear(duration: 0.08), value: speech.levels)
        .accessibilityLabel("Listening")
    }

    /// Mic, then send. One button, because two beside a field is one too many
    /// and only ever one of them is the thing you mean.
    @ViewBuilder
    private var composerButton: some View {
        if speech.isRecording {
            Button { Task { await toggleDictation() } } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.Palette.onAccent)
                    .frame(width: 13, height: 13)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Palette.alarm))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop dictating")
        } else if canSend {
            Button { Task { await send() } } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.onAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Palette.accent))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
        } else {
            Button { Task { await toggleDictation() } } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Palette.surface))
                    .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dictate")
        }
    }

    /// Existing text plus the live transcript.
    private var liveText: String {
        guard !speech.transcript.isEmpty else { return dictationBase }
        return dictationBase.isEmpty ? speech.transcript : dictationBase + " " + speech.transcript
    }

    private func toggleDictation() async {
        if speech.isRecording {
            speech.stop()
            draft = liveText
            speech.reset()
            dictationBase = ""
            focused = true
            return
        }
        dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.reset()
        await speech.toggle()
    }

    private var canSend: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && sending == false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        failure = nil

        // Snapshot history BEFORE storing this turn. Reading it afterwards
        // sent the model the same sentence twice, once as history and once as
        // the current message, and it replied "since you sent it twice".
        let history = storedHistory()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Theme.fast) { turns.append(Bubble(isUser: true, text: text)) }
        context.insert(ChatMessage(role: "user", text: text))
        try? context.save()

        sending = true
        defer { sending = false }

        let snapshots = habits.map { habit in
            HabitSnapshot(
                id: habit.id,
                name: habit.name,
                nudgeText: habit.nudgeText,
                intensity: habit.intensity,
                schedule: habit.schedule,
                isPaused: habit.isPaused,
                completionRate7d: HabitStatsService.stats(for: habit.occurrences, days: 7).completionRate,
                currentStreak: HabitStatsService.streak(for: habit.occurrences),
                longestStreak: HabitStatsService.longestStreak(for: habit.occurrences),
                notes: habit.notes,
                recent: HabitStatsService.daily(for: habit.occurrences, days: 14).map {
                    DayPoint(day: DayKey.string($0.date), done: $0.completed, of: $0.scheduled)
                },
                weekly: HabitStatsService
                    .buckets(for: habit.occurrences, component: .weekOfYear, count: 12)
                    .map { PeriodPoint(start: DayKey.string($0.label), done: $0.completed, of: $0.answered) },
                monthly: HabitStatsService
                    .buckets(for: habit.occurrences, component: .month, count: 12)
                    .map { PeriodPoint(start: DayKey.string($0.label), done: $0.completed, of: $0.answered) },
                trackedSince: HabitStatsService.firstRecord(for: habit.occurrences)
                    .map { DayKey.string($0) }
            )
        }

        var reply: AssistantReply
        switch await AssistantService.send(text, habits: snapshots, history: history) {
        case .failure(let error):
            failure = error.errorDescription
            return
        case .success(let first):
            reply = first
        }

        // The model asked for history it was not handed. Resolve it locally and
        // ask once more. Once only, so a model that keeps asking cannot loop.
        if let request = reply.dataRequest {
            let slices = historySlices(for: request)
            switch await AssistantService.send(
                text, habits: snapshots, history: history, extraHistory: slices
            ) {
            case .failure(let error):
                failure = error.errorDescription
                return
            case .success(let second):
                reply = second
            }
        }

        await applyReply(reply)
    }

    /// Day-level detail for whatever range the assistant asked about.
    private func historySlices(for request: HistoryRequest) -> [HistorySlice] {
        guard let from = DayKey.date(request.from), let to = DayKey.date(request.to) else { return [] }
        return habits
            .filter { request.habitID == nil || $0.id == request.habitID }
            .map { habit in
                HistorySlice(
                    habitID: habit.id,
                    habitName: habit.name,
                    days: HabitStatsService.range(for: habit.occurrences, from: from, to: to).map {
                        DayPoint(day: DayKey.string($0.date), done: $0.completed, of: $0.scheduled)
                    }
                )
            }
    }

    private func applyReply(_ reply: AssistantReply) async {
        // Anything irreversible waits for an explicit confirmation.
        if reply.mutations.contains(where: \.isDestructive) {
            awaitingConfirmation = PendingChange(
                reply: reply.reply,
                mutations: reply.mutations,
                summary: MutationApplier.describe(reply.mutations, habits: habits)
            )
            return
        }

        let summary = MutationApplier.apply(reply.mutations, habits: habits, context: context)
        UINotificationFeedbackGenerator().notificationOccurred(
            reply.mutations.isEmpty ? .success : .success
        )
        context.insert(ChatMessage(role: "assistant", text: reply.reply, appliedSummary: summary))
        try? context.save()

        let warning = (reply.warnings ?? []).isEmpty
            ? nil
            : "Could not apply: " + (reply.warnings ?? []).joined(separator: "; ")
        withAnimation(Theme.fast) {
            turns.append(Bubble(
                isUser: false, text: reply.reply, applied: summary, warning: warning
            ))
        }

        if !reply.mutations.isEmpty {
            await coordinator.resync(context: context)
        }
    }

    /// The model still gets continuity even though the screen starts blank.
    private func storedHistory() -> [AssistantService.Turn] {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 16
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.reversed().map {
            AssistantService.Turn(role: $0.isUser ? "user" : "assistant", text: $0.text)
        }
    }
}

struct MessageBubble: View {
    let bubble: ChatView.Bubble

    var body: some View {
        VStack(alignment: bubble.isUser ? .trailing : .leading, spacing: Theme.Space.xs) {
            Text(bubble.text)
                .font(Theme.body(16))
                .foregroundStyle(bubble.isUser ? Theme.Palette.onAccent : Theme.Palette.ink)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(bubble.isUser ? Theme.Palette.accent : Theme.Palette.surface)
                )

            if let applied = bubble.applied, !applied.isEmpty {
                Label(applied, systemImage: "checkmark")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.Palette.success)
            }
            if let warning = bubble.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.Palette.warning)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: bubble.isUser ? .trailing : .leading)
        .transition(.opacity)
    }
}

/// Thinking state with a moving label and an elapsed counter.
///
/// Three static dots for forty seconds is indistinguishable from a hang. The
/// word changes so the wait reads as progress, and the seconds counter makes
/// "this is slow" obvious rather than ambiguous.
struct TypingIndicator: View {
    @State private var phase = 0
    @State private var seconds = 0
    @State private var pulse = false

    private static let words = [
        "Thinking", "Reading your habits", "Checking the schedule",
        "Working out the timing", "Almost there",
    ]

    private var word: String {
        Self.words[min(phase, Self.words.count - 1)]
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.Palette.inkFaint)
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 1 : 0.25)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.16),
                            value: pulse
                        )
                }
            }

            Text(word)
                .font(Theme.footnote(14))
                .foregroundStyle(Theme.Palette.inkSoft)
                .contentTransition(.opacity)
                .id(word)
                .transition(.opacity)

            if seconds >= 4 {
                Text("\(seconds)s")
                    .font(Theme.caption(12).monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.surface))
        .task {
            pulse = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                seconds += 1
                // Advance the wording roughly every four seconds, stopping on
                // the last one rather than looping back to "Thinking".
                let next = min(seconds / 4, Self.words.count - 1)
                if next != phase {
                    withAnimation(Theme.motion) { phase = next }
                }
            }
        }
    }
}

/// Applies assistant mutations to the local store and returns a human summary.
/// The model proposes; this is the only thing that writes.
enum MutationApplier {
    @MainActor
    static func apply(_ mutations: [Mutation], habits: [Habit], context: ModelContext) -> String {
        guard !mutations.isEmpty else { return "" }
        var lines: [String] = []
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })

        for mutation in mutations {
            switch mutation {
            case .createHabit(let draft):
                context.insert(Habit(
                    name: draft.name,
                    nudgeText: draft.nudgeText,
                    intensity: draft.intensity,
                    schedule: draft.schedule,
                    symbol: draft.symbol,
                    tintHex: draft.tintHex
                ))
                lines.append("Added \(draft.name)")

            case .updateSchedule(let id, let schedule):
                guard let habit = byID[id] else { continue }
                // The floor is enforced here, not in the prompt. A model cannot
                // talk its way past a hard minimum interval.
                var safe = schedule
                safe.minIntervalMinutes = max(schedule.minIntervalMinutes, habit.schedule.minIntervalMinutes)
                habit.schedule = safe
                lines.append("\(habit.name): \(safe.summary)")

            case .setIntensity(let id, let intensity):
                guard let habit = byID[id] else { continue }
                habit.intensity = intensity
                lines.append("\(habit.name) is now \(intensity.title)")

            case .pauseHabit(let id, let paused):
                guard let habit = byID[id] else { continue }
                habit.isPaused = paused
                lines.append("\(paused ? "Paused" : "Resumed") \(habit.name)")

            case .deleteHabit(let id):
                guard let habit = byID[id] else { continue }
                lines.append("Removed \(habit.name)")
                context.delete(habit)

            case .updateHabit(let id, let name, let nudgeText, let variants, let symbol, let tintHex):
                guard let habit = byID[id] else { continue }
                if let name { habit.name = name }
                if let nudgeText { habit.nudgeText = nudgeText }
                if let variants { habit.nudgeVariantsRaw = variants.joined(separator: "\n") }
                if let symbol { habit.symbol = symbol }
                if let tintHex { habit.tintHex = tintHex }
                lines.append("Updated \(habit.name)")

            case .setNotes(let id, let notes):
                guard let habit = byID[id] else { continue }
                habit.notes = notes
                lines.append("Noted on \(habit.name)")

            case .logDay(let id, let day, let status):
                let touched = occurrences(on: day, habitID: id, habits: habits)
                for occurrence in touched {
                    occurrence.status = status
                    occurrence.respondedAt = .now
                }
                lines.append("Marked \(touched.count) \(status.rawValue) on \(day)")

            case .clearRange(let id, let from, let to):
                let touched = occurrences(in: from...to, habitID: id, habits: habits)
                for occurrence in touched { context.delete(occurrence) }
                lines.append("Cleared \(touched.count) from \(from) to \(to)")

            case .snoozeNext(let id, let minutes):
                guard let habit = byID[id],
                      let next = habit.occurrences
                        .filter({ $0.status == .pending && $0.scheduledAt > .now })
                        .min(by: { $0.scheduledAt < $1.scheduledAt })
                else { continue }
                next.scheduledAt = next.scheduledAt.addingTimeInterval(TimeInterval(minutes * 60))
                next.isPinned = true
                lines.append("\(habit.name) pushed \(minutes) min")
            }
        }
        try? context.save()
        return lines.joined(separator: " · ")
    }

    /// A plain-language preview, shown before anything destructive runs.
    @MainActor
    static func describe(_ mutations: [Mutation], habits: [Habit]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        return mutations.map { mutation in
            switch mutation {
            case .deleteHabit(let id):
                let name = byID[id]?.name ?? "a habit"
                let history = byID[id]?.occurrences.count ?? 0
                return "Delete \(name) and its \(history) logged nudges."
            case .clearRange(let id, let from, let to):
                let scope = id.flatMap { byID[$0]?.name } ?? "all habits"
                let count = occurrences(in: from...to, habitID: id, habits: habits).count
                return "Erase \(count) entries for \(scope), \(from) to \(to)."
            default:
                return ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    @MainActor
    private static func occurrences(
        on day: String, habitID: UUID?, habits: [Habit]
    ) -> [HabitOccurrence] {
        occurrences(in: day...day, habitID: habitID, habits: habits)
    }

    @MainActor
    private static func occurrences(
        in range: ClosedRange<String>, habitID: UUID?, habits: [Habit]
    ) -> [HabitOccurrence] {
        habits
            .filter { habitID == nil || $0.id == habitID }
            .flatMap(\.occurrences)
            .filter { range.contains(DayKey.string($0.scheduledAt)) }
    }
}


/// Everything ever said, newest first, grouped by day.
///
/// Separate from the chat itself on purpose: the transcript is working memory
/// and should open clean, but the record still has to be reachable.
struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]

    private var days: [(day: Date, items: [ChatMessage])] {
        Dictionary(grouping: messages) { Calendar.current.startOfDay(for: $0.createdAt) }
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    EmptyStateView(symbol: "clock", title: "Nothing yet")
                        .frame(maxHeight: .infinity)
                        .background(Theme.Palette.canvas)
                } else {
                    List {
                        ForEach(days, id: \.day) { group in
                            Section(header: Text(header(for: group.day))) {
                                ForEach(group.items) { message in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(message.isUser ? "You" : "Psst")
                                            .font(Theme.caption(11))
                                            .foregroundStyle(Theme.Palette.inkFaint)
                                        Text(message.text)
                                            .font(Theme.body(15))
                                            .foregroundStyle(Theme.Palette.ink)
                                        if let applied = message.appliedSummary, !applied.isEmpty {
                                            Label(applied, systemImage: "checkmark")
                                                .font(Theme.caption(12))
                                                .foregroundStyle(Theme.Palette.success)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .listRowBackground(Theme.Palette.surface)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !messages.isEmpty {
                        Button("Clear", role: .destructive) {
                            for message in messages { context.delete(message) }
                            try? context.save()
                        }
                        .foregroundStyle(Theme.Palette.alarm)
                    }
                }
            }
        }
    }

    private func header(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
