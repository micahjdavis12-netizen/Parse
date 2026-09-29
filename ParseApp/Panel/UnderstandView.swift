import SwiftUI
import ParseCore

enum PairedWorkspaceMode {
    case reading
    case editing
}

struct PairedTranslationView: View {
    @Bindable var session: SessionStore
    var mode: PairedWorkspaceMode = .reading
    @State private var codeWidth: CGFloat = 360
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let clampedCodeWidth = min(max(codeWidth, 220), max(220, geometry.size.width - 240))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    columnHeaders(codeWidth: clampedCodeWidth)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            overviewBanner
                            ForEach(rows) { row in
                                PairedLineRow(
                                    row: row,
                                    codeWidth: clampedCodeWidth,
                                    isSelected: session.highlightedLines.contains(row.number),
                                    isChanged: mode == .editing && session.lineDidChange(row.number),
                                    isEditing: mode == .editing,
                                    isGenerating: session.phase == .generating,
                                    english: englishBinding(for: row),
                                    onHover: { hovering in
                                        if hovering { session.highlight(line: row.number, origin: .hover) }
                                    },
                                    onSelect: { session.highlight(line: row.number, origin: .code) }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Color.clear
                    .frame(width: 10, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .offset(x: clampedCodeWidth - 5)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = clampedCodeWidth }
                                codeWidth = (dragStartWidth ?? clampedCodeWidth) + value.translation.width
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            }
            .onAppear { codeWidth = clampedCodeWidth }
        }
    }

    private func columnHeaders(codeWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Code")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(width: codeWidth, alignment: .leading)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            Text(mode == .editing ? "What it should do" : "What it means")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 22)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var overviewBanner: some View {
        if mode == .editing {
            editBanner
            Divider()
        } else if let overview = session.explanation?.overview, !overview.isEmpty {
            Text(overview)
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
        } else if session.phase == .explaining {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating each line with the rest of the snippet in mind…")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
    }

    private var editBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.phase == .generating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Writing the code from your English…")
                        .font(ParseTheme.captionFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let overview = session.explanation?.overview, !overview.isEmpty {
                Text(overview)
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Anything else for this whole snippet (optional)", text: $session.instruction)
                .textFieldStyle(.plain)
                .font(ParseTheme.explanationFont)
                .disabled(session.phase == .generating)
                .onSubmit { session.generateChange() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func englishBinding(for row: PairedLine) -> Binding<String> {
        Binding(
            get: { session.lineIntents[row.number] ?? row.meaning ?? "" },
            set: { session.setLineIntent(row.number, $0) }
        )
    }

    private var rows: [PairedLine] {
        guard let snippet = session.snippet else { return [] }
        return snippet.lines.enumerated().map { index, line in
            let number = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return PairedLine(
                number: number,
                code: line,
                meaning: trimmed.isEmpty ? nil : session.explanation?.meaning(forLine: number),
                isBlank: trimmed.isEmpty
            )
        }
    }
}

private struct PairedLine: Identifiable {
    var id: Int { number }
    var number: Int
    var code: String
    var meaning: String?
    var isBlank: Bool
}

private struct PairedLineRow: View {
    var row: PairedLine
    var codeWidth: CGFloat
    var isSelected: Bool
    var isChanged: Bool
    var isEditing: Bool
    var isGenerating: Bool
    @Binding var english: String
    var onHover: (Bool) -> Void
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            codeCell
                .frame(width: codeWidth, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            meaningCell
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isEditing { onSelect() }
                }
        }
        .background(rowBackground)
        .onHover(perform: onHover)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if isChanged { return Color.accentColor.opacity(0.05) }
        return .clear
    }

    private var codeCell: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(row.number)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
                .textSelection(.disabled)
                .allowsHitTesting(false)
            Text(row.code.isEmpty ? " " : row.code)
                .font(ParseTheme.monoFont)
                .foregroundStyle(row.isBlank ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var meaningCell: some View {
        Group {
            if row.isBlank {
                Text(" ")
                    .font(ParseTheme.explanationFont)
            } else if isEditing {
                TextField("What this line should do", text: $english, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(ParseTheme.explanationFont)
                    .lineLimit(1...8)
                    .disabled(isGenerating)
            } else if let meaning = row.meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(ParseTheme.explanationFont)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Translating this line…")
                    .font(ParseTheme.explanationFont)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
    }
}

struct CodeBlockView: View {
    var snippet: CodeSnippet
    var highlightedLines: Set<Int>
    var shouldScrollToHighlight: Bool
    var scrollGeneration: Int
    var onHoverLine: (Int) -> Void
    var onSelectLine: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Code")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snippet.lines.enumerated()), id: \.offset) { index, line in
                            let number = index + 1
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(number)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 28, alignment: .trailing)
                                    .textSelection(.disabled)
                                    .allowsHitTesting(false)
                                Text(line.isEmpty ? " " : line)
                                    .font(ParseTheme.monoFont)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                            .padding(.horizontal, 8)
                            .background(highlightedLines.contains(number) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectLine(number) }
                            .onHover { hovering in
                                if hovering { onHoverLine(number) }
                            }
                            .id(number)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: scrollGeneration) { _, _ in
                    guard shouldScrollToHighlight, let line = highlightedLines.sorted().first else { return }
                    proxy.scrollTo(line, anchor: .center)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }
}
