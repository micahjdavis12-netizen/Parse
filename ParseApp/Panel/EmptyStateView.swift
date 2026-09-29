import SwiftUI
import ParseCore

struct EmptyStateView: View {
    var session: SessionStore

    var body: some View {
        VStack(spacing: 6) {
            Text("Parse.")
                .font(.system(size: 17, weight: .semibold))
            Text("Your code, translated.")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if session.modelUnavailable {
                Label("Apple Intelligence is off, and no API key is set.", systemImage: "info.circle")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HotkeyLabel: View {
    var body: some View {
        HStack(spacing: 3) {
            keySymbol("option")
            keySymbol("command")
            keyText("P")
        }
        .help("Select code to translate")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Option Command P, select code to translate")
    }

    private func keySymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .semibold))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .background(keyBackground)
    }

    private func keyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 3)
            .background(keyBackground)
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
