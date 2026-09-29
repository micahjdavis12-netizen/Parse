import AppKit
import ParseCore

struct MacHostAdapter: HostAdapter {
    func currentSelection() async -> HostSelection? {
        await currentDocumentOrSelection()
    }

    func currentDocumentOrSelection() async -> HostSelection? {
        let fileName = AccessibilityBridge.focusedFileName()
        if let selected = AccessibilityBridge.selectedText(), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HostSelection(source: selected, fileName: fileName, canApplyDirectly: true)
        }
        if let document = AccessibilityBridge.focusedElementValue(), document.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
            return HostSelection(source: document, fileName: fileName, canApplyDirectly: true)
        }
        if let copied = await AccessibilityBridge.selectedTextViaCopy(), !copied.isEmpty {
            return HostSelection(source: copied, fileName: fileName, canApplyDirectly: true)
        }
        return nil
    }

    func surroundingContext(for selection: HostSelection) async -> CodeContext {
        if let value = AccessibilityBridge.focusedElementValue(), value != selection.source, value.count > selection.source.count {
            return CodeContext(surrounding: value)
        }
        return .empty
    }

    func apply(change: ProposedChange, to selection: HostSelection) async -> ApplyResult {
        if selection.canApplyDirectly, AccessibilityBridge.replaceSelectedText(change.proposedSource) {
            return .inserted
        }
        await copy(change.proposedSource)
        return .copiedFallback(reason: "The current app does not allow Parse to insert directly, so the proposed code was copied.")
    }

    func copy(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
