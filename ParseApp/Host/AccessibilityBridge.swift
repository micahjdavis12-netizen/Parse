import AppKit
@preconcurrency import ApplicationServices

enum AccessibilityBridge {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    static func selectedText() -> String? {
        guard isTrusted(prompt: false) else { return nil }
        guard let focused = focusedElement() else { return nil }
        if let selected = stringAttribute(focused, kAXSelectedTextAttribute) , !selected.isEmpty {
            return selected
        }
        if let markerText = selectedTextFromMarkers(focused), !markerText.isEmpty {
            return markerText
        }
        return nil
    }

    static func selectedTextViaCopy() async -> String? {
        guard isTrusted(prompt: false) else { return nil }
        await Task.yield()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: copySelectionFromFrontmostApp())
            }
        }
    }

    private static func copySelectionFromFrontmostApp() -> String? {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let changeCount = pasteboard.changeCount
        guard postCommandC() else { return nil }

        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                let copied = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                if let previous {
                    pasteboard.setString(previous, forType: .string)
                }
                if let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return copied
                }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private static func postCommandC() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func focusedElementValue() -> String? {
        guard isTrusted(prompt: false), let focused = focusedElement() else { return nil }
        return stringAttribute(focused, kAXValueAttribute)
    }

    static func focusedFileName() -> String? {
        guard isTrusted(prompt: false) else { return nil }
        let system = AXUIElementCreateSystemWide()
        var app: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let appElement = app
        else { return nil }
        let axApp = appElement as! AXUIElement
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success else {
            return nil
        }
        let axWindow = window as! AXUIElement
        return stringAttribute(axWindow, kAXTitleAttribute)
    }

    static func replaceSelectedText(_ text: String) -> Bool {
        guard isTrusted(prompt: false), let focused = focusedElement() else { return false }
        let result = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success else { return nil }
        return value.map { $0 as! AXUIElement }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private static func selectedTextFromMarkers(_ element: AXUIElement) -> String? {
        var range: AnyObject?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &range
        )
        guard rangeError == .success, let range else { return nil }
        var text: AnyObject?
        let textError = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            range,
            &text
        )
        guard textError == .success else { return nil }
        return text as? String
    }
}
