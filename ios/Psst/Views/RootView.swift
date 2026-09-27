import SwiftData
import SwiftUI

/// Three tabs, with swipe navigation from the screen edges.
///
/// Paged `TabView` was the obvious way to get Snapchat-style swiping, and it
/// does not work here: a paging scroll view and a `List` row's swipe actions
/// compete for the same horizontal drag, and paging wins. Swiping left on a
/// row navigated to the next tab instead of revealing Delete.
///
/// So the tab bar stays the real system control, and swiping is restricted to
/// narrow zones at the screen edges where no row gesture lives.
struct RootView: View {
    @Environment(NotificationResponder.self) private var responder
    @State private var screen = Screen.home

    enum Screen: Int, Hashable, CaseIterable {
        case chat, home, habits
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab(value: Screen.chat) {
                ChatView(embedded: true)
            } label: {
                Label("Psst", systemImage: "bubble.left.and.bubble.right")
            }

            Tab(value: Screen.home) {
                HomeView()
            } label: {
                Label("Home", systemImage: "house")
            }

            Tab(value: Screen.habits) {
                HabitsView()
            } label: {
                Label("Habits", systemImage: "square.stack")
            }
        }
        .tint(Theme.Palette.accent)
        .overlay(alignment: .leading) { edge(.leading) }
        .overlay(alignment: .trailing) { edge(.trailing) }
        .sheet(isPresented: Binding(
            get: { responder.showWeeklyReview },
            set: { responder.showWeeklyReview = $0 }
        )) {
            WeeklyReviewView()
        }
    }

    /// An invisible strip. Narrow enough that a row swipe never starts inside
    /// it, wide enough to catch a deliberate edge drag.
    private func edge(_ side: HorizontalEdge) -> some View {
        Color.clear
            .frame(width: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        move(by: value.translation.width > 0 ? -1 : 1)
                    }
            )
            .padding(.bottom, 90)
            .allowsHitTesting(true)
            .accessibilityHidden(true)
            .ignoresSafeArea(.keyboard)
            .opacity(side == .leading ? 1 : 1)
    }

    private func move(by offset: Int) {
        let order = Screen.allCases
        guard let index = order.firstIndex(of: screen) else { return }
        let next = index + offset
        guard order.indices.contains(next) else { return }
        withAnimation(Theme.motion) { screen = order[next] }
    }
}
