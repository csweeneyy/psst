import SwiftUI

/// Full-width filled button. One per screen.
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var enabled: Bool = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Theme.Space.s) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title)
            }
            .font(Theme.title(17))
            .foregroundStyle(enabled ? Theme.Palette.onAccent : Theme.Palette.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                    .fill(enabled ? Theme.Palette.accent : Theme.Palette.well)
            )
        }
        .disabled(!enabled)
        .pressable()
    }
}

/// Segmented selector. Matches `UISegmentedControl` proportions.
struct ChipRow<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var symbol: ((T) -> String)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isOn = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 5) {
                        if let symbol { Image(systemName: symbol(option)).font(.system(size: 11, weight: .semibold)) }
                        Text(label(option))
                    }
                    .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isOn ? Theme.Palette.surface : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.Palette.well)
        )
        .animation(Theme.fast, value: selection)
    }
}

/// Section header, matching grouped-list header treatment.
struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .regular))
            .tracking(0.3)
            .foregroundStyle(Theme.Palette.inkSoft)
            // Aligns with the text inside the card below it, not the card edge.
            .padding(.leading, Theme.Space.l)
    }
}

/// Background for a pinned bottom bar.
///
/// Without this, scrolled content shows through the gaps around a floating
/// control and the screen reads as broken rather than layered.
struct BottomBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            LinearGradient(
                colors: [Theme.Palette.canvas.opacity(0), Theme.Palette.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .offset(y: -28)
            .allowsHitTesting(false)
        }
        .background(Theme.Palette.canvas)
    }
}

extension View {
    func bottomBar() -> some View { modifier(BottomBarBackground()) }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Palette.inkFaint)
            Text(title)
                .font(Theme.title(17))
                .foregroundStyle(Theme.Palette.ink)
            if let message {
                Text(message)
                    .font(Theme.footnote(14))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
    }
}
