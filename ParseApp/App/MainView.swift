import SwiftUI
import ParseCore

struct MainView: View {
    @Bindable var session: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HSplitView {
            SidebarView(session: session)
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
            WorkspaceView(session: session)
                .frame(minWidth: 360, minHeight: 320)
        }
        .background(.background)
        .onReceive(NotificationCenter.default.publisher(for: .parseShowMainWindow)) { _ in
            openWindow(id: "main")
        }
        .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            session.placeWindowIfNeeded()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.utf8-plain-text") }) {
            _ = textProvider.loadObject(ofClass: String.self) { value, _ in
                if let value {
                    DispatchQueue.main.async {
                        session.loadPasted(value)
                    }
                }
            }
            return true
        }
        if let fileProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) {
            fileProvider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    session.loadPasted(text, fileName: url.lastPathComponent)
                }
            }
            return true
        }
        return false
    }
}

struct SidebarView: View {
    @Bindable var session: SessionStore
    @State private var pendingDelete: [HistoryItem] = []
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    session.newSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("New")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            List {
                ForEach(session.history) { item in
                    HistoryRow(
                        item: item,
                        isSelected: session.selectedHistoryID == item.id,
                        onOpen: { session.openHistoryItem(item) },
                        onDelete: {
                            pendingDelete = [item]
                            showDeleteConfirm = true
                        }
                    )
                    .contextMenu {
                        Button("Copy Code") {
                            Task { await session.host.copy(item.source) }
                        }
                        Button("Delete", role: .destructive) {
                            pendingDelete = [item]
                            showDeleteConfirm = true
                        }
                    }
                }
                .onDelete { indexSet in
                    pendingDelete = indexSet.map { session.history[$0] }
                    showDeleteConfirm = !pendingDelete.isEmpty
                }
            }
            .listStyle(.sidebar)
        }
        .background(.background)
        .alert(deleteTitle, isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                session.deleteHistoryItems(pendingDelete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage(pendingDelete))
        }
    }

    private var deleteTitle: String {
        pendingDelete.count > 1 ? "Delete these translations?" : "Delete this translation?"
    }

    private func deleteMessage(_ items: [HistoryItem]) -> String {
        if items.count == 1 {
            return "“\(items[0].title)” will be removed from Recent."
        }
        return "\(items.count) translations will be removed from Recent."
    }
}

struct HistoryRow: View {
    var item: HistoryItem
    var isSelected: Bool
    var onOpen: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(ParseTheme.headerFont)
                    .lineLimit(1)
                Text(item.language.name)
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
                .help("Delete")
                .accessibilityLabel("Delete")
                .accessibilityAddTraits(.isButton)
                .highPriorityGesture(TapGesture().onEnded { onDelete() })
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}

struct WorkspaceView: View {
    @Bindable var session: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(session: session)
            Divider()
            workspaceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            WorkspaceFooter(session: session)
        }
        .background(.background)
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if session.snippet != nil, session.phase == .explaining || session.phase == .understand {
            PairedTranslationView(session: session, mode: .reading)
        } else if session.snippet != nil, session.phase == .describe || session.phase == .generating {
            PairedTranslationView(session: session, mode: .editing)
        } else {
            HSplitView {
                if let snippet = session.snippet, session.phase != .empty {
                    CodeBlockView(
                        snippet: snippet,
                        highlightedLines: session.highlightedLines,
                        shouldScrollToHighlight: session.highlightOrigin == .meaning,
                        scrollGeneration: session.scrollGeneration,
                        onHoverLine: { session.highlight(line: $0, origin: .hover) },
                        onSelectLine: { session.highlight(line: $0, origin: .code) }
                    )
                    .frame(minWidth: 220)
                }
                phaseContent
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .empty:
            EmptyStateView(session: session)
        case .explaining, .understand:
            PairedTranslationView(session: session, mode: .reading)
        case .describe, .generating:
            PairedTranslationView(session: session, mode: .editing)
        case .review:
            ReviewView(session: session)
        }
    }
}

struct WorkspaceHeader: View {
    @Bindable var session: SessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            HotkeyLabel()
            VStack(alignment: .leading, spacing: 1) {
                Text(session.languageHeader)
                    .font(ParseTheme.headerFont)
                    .lineLimit(1)
                if let name = session.snippet?.fileName, !name.isEmpty {
                    Text(name)
                        .font(ParseTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if session.snippet != nil {
                Picker("Depth", selection: Binding(
                    get: { session.depth },
                    set: { session.changeDepth($0) }
                )) {
                    ForEach(ExplanationDepth.allCases) { depth in
                        Text(depth.title).tag(depth)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 160)
                .disabled(session.phase != .understand)
            }
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

struct WorkspaceFooter: View {
    @Bindable var session: SessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                if session.errorSuggestsAPIKey {
                    Button("+API key") {
                        openSettings()
                    }
                    .controlSize(.small)
                }
            } else if let apply = session.applyMessage {
                Text(apply)
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let hint = session.cloudHint {
                Text(hint)
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if session.phase == .describe {
                Text("Rewrite any line in English. Parse writes the code.")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch session.phase {
        case .empty:
            Button("Paste") { session.pasteFromClipboard() }
                .buttonStyle(.bordered)
        case .understand:
            Button("Edit") { session.beginEdit() }
                .buttonStyle(.borderedProminent)
                .disabled(session.explanation == nil)
        case .explaining:
            ProgressView()
                .controlSize(.small)
        case .describe:
            Button("Cancel") { session.cancelEdit() }
                .buttonStyle(.borderless)
            Button("Generate") { session.generateChange() }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canGenerateChange)
        case .review:
            Button("Cancel") { session.cancelEdit() }
                .buttonStyle(.borderless)
            Button("Regenerate") { session.generateChange(isRetry: true) }
                .buttonStyle(.borderless)
            Button("Copy Change") { session.copyCode() }
                .buttonStyle(.bordered)
            Button(insertTitle) { session.insertChange() }
                .buttonStyle(.borderedProminent)
        case .generating:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var insertTitle: String {
        if let change = session.proposedChange, change.hasSafetyFlags, !session.safetyAcknowledged {
            return "Review Risk"
        }
        return "Insert Change"
    }
}
