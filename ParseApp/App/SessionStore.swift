import AppKit
import Foundation
import Observation
import ParseCore
import SwiftUI

enum SessionPhase: Equatable {
    case empty
    case explaining
    case understand
    case describe
    case generating
    case review
}

enum HighlightOrigin: Equatable {
    case hover
    case code
    case meaning
}

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    var phase: SessionPhase = .empty
    var snippet: CodeSnippet?
    var explanation: Explanation?
    var depth: ExplanationDepth = SessionStore.preferredDepth()
    var instruction: String = ""
    var lineIntents: [Int: String] = [:]
    var originalLineIntents: [Int: String] = [:]
    var proposedChange: ProposedChange?
    var highlightedLines: Set<Int> = []
    var highlightOrigin: HighlightOrigin = .hover
    var scrollGeneration: Int = 0
    var selectedSectionID: UUID?
    var errorMessage: String?
    var cloudHint: String?
    var applyMessage: String?
    var safetyAcknowledged: Bool = false
    var lastDecision: RouteDecision?
    var hostSelection: HostSelection?

    var history: [HistoryItem]
    var selectedHistoryID: UUID?

    var cloudSettings = CloudSettings()
    let host = MacHostAdapter()

    var languageHeader: String {
        snippet?.language.headerText ?? "Select code to translate"
    }

    var canUseOnDevice: Bool {
        AppleFoundationProvider().isAvailable
    }

    var canUseCloud: Bool {
        OpenAICompatibleProvider(configuration: cloudSettings.configuration).isAvailable
    }

    var engine: TranslationEngine {
        let onDevice = AppleFoundationProvider()
        let cloud: (any ModelProvider)? = canUseCloud
            ? OpenAICompatibleProvider(configuration: cloudSettings.configuration)
            : nil
        return TranslationEngine(
            onDevice: onDevice,
            cloud: cloud,
            router: ModelRouter(cloudAvailable: canUseCloud, onDeviceAvailable: onDevice.isAvailable)
        )
    }

    var modelUnavailable: Bool {
        !engine.anyProviderAvailable
    }

    var canGenerateChange: Bool {
        if !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return currentLineIntents().contains(where: \.didChange)
    }

    func lineDidChange(_ number: Int) -> Bool {
        let current = (lineIntents[number] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (originalLineIntents[number] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return current != original
    }

    func setLineIntent(_ number: Int, _ english: String) {
        var next = lineIntents
        next[number] = english
        lineIntents = next
    }

    var cleanSource: String {
        if let proposedChange {
            return proposedChange.proposedSource
        }
        return snippet?.source ?? ""
    }

    init() {
        history = HistoryStore.load().sorted { $0.updatedAt > $1.updatedAt }
    }

    private var hasPlacedWindow = false

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .parseShowMainWindow, object: nil)
        if let window = WindowSizing.mainWindow() {
            placeWindowIfNeeded(window)
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func placeWindowIfNeeded(_ window: NSWindow? = WindowSizing.mainWindow()) {
        guard !hasPlacedWindow, let window else { return }
        WindowSizing.fitToScreen(window)
        hasPlacedWindow = true
    }

    var isGrabbing = false

    func grabFromScreen() {
        guard !isGrabbing else { return }
        Task { await grabFromScreenNow() }
    }

    func loadPasted(_ text: String, fileName: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        beginNewWorkingSession()
        hostSelection = HostSelection(source: trimmed, fileName: fileName, canApplyDirectly: false)
        Task { await explain(source: trimmed, fileName: fileName) }
        showMainWindow()
    }

    func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            loadPasted(text)
        }
    }

    func newSession() {
        persistCurrent()
        resetWorkingState()
        selectedHistoryID = nil
        showMainWindow()
    }

    func openHistoryItem(_ item: HistoryItem) {
        persistCurrent()
        selectedHistoryID = item.id
        snippet = CodeSnippet(
            source: item.source,
            fileName: item.fileName,
            language: item.language,
            surrounding: item.surrounding
        )
        explanation = item.explanation
        depth = item.depth
        instruction = item.instruction
        lineIntents = [:]
        originalLineIntents = [:]
        if let proposed = item.proposedSource {
            proposedChange = ChangeEngine.proposedChange(
                original: item.source,
                proposed: proposed,
                whatChangedEnglish: item.whatChangedEnglish ?? "",
                usedCloud: item.usedCloud
            )
            phase = .review
        } else if item.explanation != nil {
            phase = .understand
            if let first = item.explanation?.lineMeanings.first {
                highlight(line: first.line)
            } else {
                highlight(section: item.explanation?.sections.first)
            }
        } else if !item.source.isEmpty {
            phase = .understand
        } else {
            phase = .empty
        }
        errorMessage = nil
        applyMessage = nil
        hostSelection = HostSelection(source: item.source, fileName: item.fileName, canApplyDirectly: false)
    }

    func deleteHistoryItem(_ item: HistoryItem) {
        deleteHistoryItems([item])
    }

    func deleteHistoryItems(_ items: [HistoryItem]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        let deletingCurrent = selectedHistoryID.map(ids.contains) ?? false
        history.removeAll { ids.contains($0.id) }
        HistoryStore.save(history)
        if deletingCurrent {
            resetWorkingState()
            selectedHistoryID = nil
        }
    }

    func reset() {
        persistCurrent()
        resetWorkingState()
        selectedHistoryID = nil
    }

    var errorSuggestsAPIKey: Bool {
        guard let errorMessage else { return false }
        return ParseError.isContextLimitMessage(errorMessage)
    }

    func retryTranslationWithAPIKey() {
        guard canUseCloud, errorSuggestsAPIKey, let snippet else { return }
        Task {
            await explain(
                source: snippet.source,
                fileName: snippet.fileName,
                surrounding: snippet.surrounding,
                replacingCurrent: true
            )
        }
    }

    func changeDepth(_ newDepth: ExplanationDepth) {
        depth = newDepth
        UserDefaults.standard.set(newDepth.rawValue, forKey: Self.depthPreferenceKey)
        guard let snippet else { return }
        Task { await explain(source: snippet.source, fileName: snippet.fileName, surrounding: snippet.surrounding, replacingCurrent: true) }
    }

    func beginEdit() {
        guard explanation != nil else { return }
        seedLineIntents()
        phase = .describe
        applyMessage = nil
        errorMessage = nil
    }

    func cancelEdit() {
        if explanation != nil {
            phase = .understand
        } else {
            phase = .empty
        }
        proposedChange = nil
        applyMessage = nil
        safetyAcknowledged = false
    }

    func generateChange(isRetry: Bool = false) {
        Task { await generate(isRetry: isRetry) }
    }

    func copyCode() {
        let text = cleanSource
        guard !text.isEmpty else { return }
        Task {
            await host.copy(text)
            applyMessage = "Copied code."
        }
    }

    func copySnippetSource() {
        guard let source = snippet?.source, !source.isEmpty else { return }
        Task {
            await host.copy(source)
            applyMessage = "Copied code."
        }
    }

    func copyExplanation() {
        guard let explanation else { return }
        let lines = explanation.lineMeanings
            .sorted { $0.line < $1.line }
            .map { "L\($0.line)  \($0.meaning)" }
        let text = ([explanation.overview] + lines)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        Task {
            await host.copy(text)
            applyMessage = "Copied explanation."
        }
    }

    func insertChange() {
        guard let proposedChange else { return }
        if proposedChange.hasSafetyFlags, !safetyAcknowledged {
            safetyAcknowledged = true
            return
        }
        Task {
            let selection = hostSelection ?? HostSelection(source: proposedChange.originalSource, canApplyDirectly: false)
            let result = await host.apply(change: proposedChange, to: selection)
            switch result {
            case .inserted:
                applyMessage = "Inserted the change."
                snippet?.source = proposedChange.proposedSource
                persistCurrent()
            case .copiedFallback(let reason):
                applyMessage = reason
            case .cancelled:
                break
            case .failed(let message):
                errorMessage = message
            }
        }
    }

    func highlight(section: ExplanationSection?) {
        selectedSectionID = section?.id
        highlightOrigin = .hover
        if let section {
            highlightedLines = Set(section.lineRange)
        } else {
            highlightedLines = []
        }
    }

    func highlight(line: Int, origin: HighlightOrigin = .hover) {
        highlightedLines = [line]
        highlightOrigin = origin
        selectedSectionID = explanation?.sections.first { $0.lineRange.contains(line) }?.id
        if origin != .hover {
            scrollGeneration += 1
        }
    }

    private var explainGeneration = UUID()

    private func grabFromScreenNow() async {
        isGrabbing = true
        defer {
            isGrabbing = false
            RegionCaptureController.shared.restoreHiddenWindows()
        }
        errorMessage = nil

        if !AccessibilityBridge.isTrusted(prompt: true) {
            errorMessage = "Allow Accessibility for Parse so it can read the code you select to translate."
            showMainWindow()
            return
        }

        guard let pick = await RegionCaptureController.shared.pickRegion() else { return }
        guard let selection = EditorLocator.selection(for: pick) else {
            errorMessage = "Couldn’t find code to translate there. Click inside the editor that has it."
            showMainWindow()
            return
        }

        beginNewWorkingSession()
        hostSelection = selection
        showMainWindow()
        await explain(source: selection.source, fileName: selection.fileName)
    }

    private func explain(
        source: String,
        fileName: String?,
        surrounding: String? = nil,
        replacingCurrent: Bool = false
    ) async {
        errorMessage = nil
        applyMessage = nil
        proposedChange = nil
        explanation = nil

        let language = engine.detectLanguage(code: source, fileName: fileName, hint: nil)
        let snippet = CodeSnippet(source: source, fileName: fileName, language: language, surrounding: surrounding)
        self.snippet = snippet
        phase = .explaining
        if !replacingCurrent {
            upsertHistoryDraft(snippet: snippet)
        }

        let generation = UUID()
        explainGeneration = generation

        do {
            guard engine.anyProviderAvailable else {
                errorMessage = ParseError.modelUnavailable.localizedDescription
                persistCurrent()
                return
            }
            let explanation = try await engine.explain(snippet: snippet, depth: depth)
            guard explainGeneration == generation else { return }
            self.explanation = explanation
            self.snippet?.language = explanation.language.identifier == "unknown" ? language : explanation.language
            phase = .understand
            if let firstLine = explanation.lineMeanings.first {
                highlight(line: firstLine.line)
            } else {
                highlight(section: explanation.sections.first)
            }
            persistCurrent()
        } catch is CancellationError {
            if explainGeneration == generation {
                phase = snippet.source.isEmpty ? .empty : .understand
            }
        } catch {
            guard explainGeneration == generation else { return }
            errorMessage = error.localizedDescription
            phase = .understand
            persistCurrent()
        }
    }

    private func generate(isRetry: Bool) async {
        guard let snippet else { return }
        let intents = currentLineIntents()
        let request = EditRequest(
            instruction: instruction,
            snippet: snippet,
            explanation: explanation,
            lineIntents: intents,
            isRetry: isRetry
        )
        phase = .generating
        errorMessage = nil
        applyMessage = nil
        safetyAcknowledged = false
        do {
            let (change, decision) = try await engine.propose(request: request)
            proposedChange = change
            lastDecision = decision
            cloudHint = decision.showCloudHint
                ? "Add an API key in Settings for large files and bigger edits."
                : nil
            phase = .review
            persistCurrent()
        } catch {
            phase = .describe
            errorMessage = error.localizedDescription
        }
    }

    private func beginNewWorkingSession() {
        persistCurrent()
        resetWorkingState()
        selectedHistoryID = UUID()
    }

    private func resetWorkingState() {
        phase = .empty
        snippet = nil
        explanation = nil
        instruction = ""
        lineIntents = [:]
        originalLineIntents = [:]
        proposedChange = nil
        highlightedLines = []
        highlightOrigin = .hover
        selectedSectionID = nil
        errorMessage = nil
        cloudHint = nil
        applyMessage = nil
        safetyAcknowledged = false
        lastDecision = nil
        hostSelection = nil
        depth = Self.preferredDepth()
    }

    private func upsertHistoryDraft(snippet: CodeSnippet) {
        let id = selectedHistoryID ?? UUID()
        selectedHistoryID = id
        let item = HistoryItem(
            id: id,
            title: HistoryItem.title(fileName: snippet.fileName, language: snippet.language, source: snippet.source),
            source: snippet.source,
            fileName: snippet.fileName,
            language: snippet.language,
            surrounding: snippet.surrounding,
            depth: depth
        )
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
        } else {
            history.insert(item, at: 0)
        }
        HistoryStore.save(history)
    }

    private func persistCurrent() {
        guard let snippet, !snippet.source.isEmpty else { return }
        let id = selectedHistoryID ?? UUID()
        selectedHistoryID = id
        let item = HistoryItem(
            id: id,
            createdAt: history.first(where: { $0.id == id })?.createdAt ?? .now,
            updatedAt: .now,
            title: HistoryItem.title(fileName: snippet.fileName, language: snippet.language, source: snippet.source),
            source: snippet.source,
            fileName: snippet.fileName,
            language: snippet.language,
            surrounding: snippet.surrounding,
            explanation: explanation,
            depth: depth,
            instruction: instruction,
            proposedSource: proposedChange?.proposedSource,
            whatChangedEnglish: proposedChange?.whatChangedEnglish,
            usedCloud: proposedChange?.usedCloud ?? false
        )
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
        } else {
            history.insert(item, at: 0)
        }
        history.sort { $0.updatedAt > $1.updatedAt }
        HistoryStore.save(history)
    }

    private static let depthPreferenceKey = "parse.explanationDepth"

    static func preferredDepth() -> ExplanationDepth {
        guard let raw = UserDefaults.standard.string(forKey: depthPreferenceKey),
              let depth = ExplanationDepth(rawValue: raw) else {
            return .simple
        }
        return depth
    }

    private func seedLineIntents() {
        guard let snippet else {
            lineIntents = [:]
            originalLineIntents = [:]
            return
        }
        var next: [Int: String] = [:]
        var originals: [Int: String] = [:]
        for (index, line) in snippet.lines.enumerated() {
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let meaning = explanation?.meaning(forLine: number) ?? ""
            next[number] = meaning
            originals[number] = meaning
        }
        lineIntents = next
        originalLineIntents = originals
    }

    private func currentLineIntents() -> [LineIntent] {
        guard let snippet else { return [] }
        return snippet.lines.enumerated().compactMap { index, line in
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let english = lineIntents[number] ?? explanation?.meaning(forLine: number) ?? ""
            let original = originalLineIntents[number] ?? explanation?.meaning(forLine: number) ?? ""
            return LineIntent(
                line: number,
                source: line,
                english: english,
                originalEnglish: original
            )
        }
    }
}

extension Notification.Name {
    static let parseShowMainWindow = Notification.Name("parseShowMainWindow")
}
