import SwiftData
import SwiftUI

/// First run.
///
/// Doubles as the only place the app explains itself. The three tiers are the
/// whole design and they are otherwise invisible until you happen to open the
/// intensity picker.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(NudgeCoordinator.self) private var coordinator
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    @State private var page = 0
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                intro.tag(0)
                tiers.tag(1)
                start.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            controls
        }
        .background(Theme.Palette.canvas)
    }

    // MARK: Pages

    private var intro: some View {
        page(
            mark: mark,
            title: "Reminders you\nactually answer.",
            body: "A habit here is a notification. Everything else exists to make answering one take a single tap, from wherever you already are."
        )
    }

    private var tiers: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Spacer(minLength: 0)
            Text("Three ways to\nbe interrupted.")
                .font(Theme.largeTitle(32))
                .displayTracking()
                .foregroundStyle(Theme.Palette.ink)

            VStack(spacing: Theme.Space.m) {
                ForEach(Intensity.allCases) { intensity in
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: intensity.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(color(for: intensity))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(color(for: intensity).opacity(0.12)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(intensity.title)
                                .font(Theme.title(16))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(intensity.blurb)
                                .font(Theme.footnote(14))
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.m)
                    .card()
                }
            }

            Text("You pick per habit. A posture nudge should not be allowed to break a Focus mode; a medication reminder should.")
                .font(Theme.footnote(14))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.bottom, Theme.Space.xl)
    }

    private var start: some View {
        page(
            mark: Image(systemName: "bell.badge")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.Palette.ink)
                .frame(height: 120),
            title: "One thing\nto allow.",
            body: "Psst needs permission to send notifications. Without it there is no app, only a list."
        )
    }

    private var mark: some View {
        ZStack {
            Circle().fill(Theme.Palette.ink).frame(width: 120, height: 120)
            Image(systemName: "dot.radiowaves.right")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(Theme.Palette.canvas)
        }
        .frame(height: 120)
    }

    private func page(mark: some View, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Spacer(minLength: 0)
            mark
            Text(title)
                .font(Theme.largeTitle(34))
                .displayTracking()
                .foregroundStyle(Theme.Palette.ink)
            Text(body)
                .font(Theme.body(17))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.bottom, Theme.Space.xl)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: Theme.Space.m) {
            if page < 2 {
                PrimaryButton(title: "Continue") {
                    withAnimation(Theme.motion) { page += 1 }
                }
            } else {
                PrimaryButton(title: "Allow notifications", enabled: !working) {
                    Task { await finish(withSamples: false) }
                }
                Button("Allow, and fill it with sample habits") {
                    Task { await finish(withSamples: true) }
                }
                .font(Theme.body(16))
                .foregroundStyle(Theme.Palette.inkSoft)
                .disabled(working)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.l)
    }

    private func color(for intensity: Intensity) -> Color {
        switch intensity {
        case .gentle: Theme.Palette.success
        case .standard: Theme.Palette.ink
        case .alarm: Theme.Palette.alarm
        }
    }

    private func finish(withSamples: Bool) async {
        working = true
        await coordinator.requestPermissions()
        if withSamples {
            SampleData.install(into: context)
            await coordinator.resync(context: context)
        }
        withAnimation(Theme.motion) { hasOnboarded = true }
    }
}
