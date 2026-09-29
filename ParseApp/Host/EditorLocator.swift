import AppKit
@preconcurrency import ApplicationServices
import ParseCore

enum EditorLocator {
    static func selection(for pick: ScreenPick) -> HostSelection? {
        guard AccessibilityBridge.isTrusted(prompt: false) else { return nil }
        guard let app = application(atCocoa: pick.point) else { return nil }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let axPoint = axPoint(fromCocoa: pick.point)
        for window in windows(of: app, containing: axPoint, or: pick.point) {
            let hit = element(in: window, atAX: axPoint) ?? element(in: window, atAX: pick.point)
            if let hit, let code = codeGroup(from: hit), let selection = selection(fromCodeGroup: code) {
                return selection
            }
        }
        guard let hit = element(in: app, atAX: axPoint)
            ?? element(in: app, atAX: pick.point)
            ?? element(atCocoa: pick.point)
            ?? element(atCocoaFlipped: pick.point)
        else { return nil }

        if let code = codeGroup(from: hit), let selection = selection(fromCodeGroup: code) {
            return selection
        }
        for box in editorFields(from: hit, containing: axPoint, or: pick.point) {
            if let selection = selection(fromTextBox: box) {
                return selection
            }
        }
        if let focused = focusedElement(in: app) {
            for element in uniqued([focused] + nearbyEditors(around: focused)) {
                let role = string(element, kAXRoleAttribute) ?? ""
                guard isTextBox(element, role: role) else { continue }
                if let selection = selection(fromTextBox: element) {
                    return selection
                }
            }
        }
        return nil
    }

    static func editorHighlight(atCocoa point: CGPoint) -> CGRect? {
        guard AccessibilityBridge.isTrusted(prompt: false) else { return nil }
        guard let app = applicationUnderOverlay(atCocoa: point) else { return nil }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let axPoint = axPoint(fromCocoa: point)
        let hit = element(in: app, atAX: axPoint) ?? element(in: app, atAX: point)
        guard let hit else { return nil }
        if let code = codeGroup(from: hit), let frame = frame(of: code), frame.width > 40, frame.height > 40 {
            return cocoaRect(fromAX: frame)
        }
        let boxes = editorFields(from: hit, containing: axPoint, or: point)
        if let frame = boxes.compactMap({ frame(of: $0) }).min(by: { area($0) < area($1) }) {
            return cocoaRect(fromAX: frame)
        }

        var best: (score: Int, frame: CGRect)?
        let candidates = uniqued(ancestors(of: hit, limit: 16) + nearbyEditors(around: hit))
        for element in candidates {
            guard let frame = frame(of: element), frame.width > 24, frame.height > 16 else { continue }
            let expanded = frame.insetBy(dx: -6, dy: -6)
            guard expanded.contains(axPoint) || expanded.contains(point) else { continue }
            let score = highlightScore(element, frame: frame)
            if score > 0, score > (best?.score ?? Int.min) {
                best = (score, frame)
            }
        }
        return best.map { cocoaRect(fromAX: $0.frame) }
    }

    private static func applicationUnderOverlay(atCocoa point: CGPoint) -> AXUIElement? {
        let parsePID = ProcessInfo.processInfo.processIdentifier
        let axPoint = axPoint(fromCocoa: point)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in info {
            let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber
            let pid = pidNumber?.int32Value ?? 0
            if pid == 0 || pid == parsePID { continue }
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let width = bounds["Width"],
                  let height = bounds["Height"]
            else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            if rect.contains(axPoint) || rect.contains(point) {
                return AXUIElementCreateApplication(pid_t(pid))
            }
        }
        return nil
    }

    private static func element(in app: AXUIElement, atAX point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit)
        guard error == .success else { return nil }
        return hit
    }

    private static func highlightScore(_ element: AXUIElement, frame: CGRect) -> Int {
        let role = string(element, kAXRoleAttribute) ?? ""
        if ignoredRoles.contains(role) { return -1 }
        if role == (kAXApplicationRole as String) { return -1 }
        if role == (kAXWindowRole as String) { return 1 }

        let roleDescription = (string(element, kAXRoleDescriptionAttribute) ?? "").lowercased()
        let description = (string(element, kAXDescriptionAttribute) ?? "").lowercased()
        var score = 8
        if role == (kAXTextAreaRole as String) { score += 100 }
        if role == (kAXTextFieldRole as String) { score += 50 }
        if role == "AXWebArea" { score += 55 }
        if role == "AXScrollArea" { score += 35 }
        if role == (kAXGroupRole as String) { score += 8 }
        if roleDescription.contains("editor") || description.contains("editor") || description.contains("source") {
            score += 90
        }
        if frame.height > 80, frame.width > 160 { score += 20 }
        if frame.width * frame.height > 1_200_000 { score -= 40 }
        return score
    }

    private static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? rect.maxY
        return CGRect(x: rect.origin.x, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func windows(of app: AXUIElement, containing axPoint: CGPoint, or cocoaPoint: CGPoint) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let value
        else { return [] }
        let cf = value as CFTypeRef
        guard CFGetTypeID(cf) == CFArrayGetTypeID() else { return [] }
        let array = cf as! CFArray
        let windows = (0..<CFArrayGetCount(array)).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: AXUIElement.self)
        }
        return windows.filter { window in
            guard let frame = frame(of: window) else { return false }
            let expanded = frame.insetBy(dx: -6, dy: -6)
            return expanded.contains(axPoint) || expanded.contains(cocoaPoint)
        }
    }

    private static func codeGroup(from element: AXUIElement) -> AXUIElement? {
        for node in ancestors(of: element, limit: 16) {
            let roleDescription = (string(node, kAXRoleDescriptionAttribute) ?? "").lowercased()
            let description = (string(node, kAXDescriptionAttribute) ?? "").lowercased()
            if roleDescription == "code" || description.contains("editor group") {
                return node
            }
        }
        return nil
    }

    private static func selection(fromCodeGroup group: AXUIElement) -> HostSelection? {
        var best: (count: Int, text: String, name: String?)?
        var budget = 0
        walk(group, budget: &budget, maxNodes: 800) { element in
            let role = string(element, kAXRoleAttribute) ?? ""
            guard role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) else { return }
            guard let raw = string(element, kAXValueAttribute) else { return }
            let text = cleanedSource(raw)
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            guard !text.localizedCaseInsensitiveContains("workbench.html") else { return }
            if text.count > (best?.count ?? 0) {
                let description = string(element, kAXDescriptionAttribute)
                best = (text.count, text, editorName(from: description))
            }
        }
        guard let best else { return nil }
        return HostSelection(source: best.text, fileName: best.name, canApplyDirectly: true)
    }

    private static func editorName(from description: String?) -> String? {
        guard let description else { return nil }
        let name = description
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, !name.localizedCaseInsensitiveContains("editor group") else { return nil }
        return name
    }

    private static func editorFields(from hit: AXUIElement, containing axPoint: CGPoint, or cocoaPoint: CGPoint) -> [AXUIElement] {
        let window = ancestors(of: hit, limit: 20).first {
            string($0, kAXRoleAttribute) == (kAXWindowRole as String)
        }
        let windowArea = window.flatMap(frame(of:)).map(area) ?? .greatestFiniteMagnitude
        let searchRoot = ancestors(of: hit, limit: 20).first {
            string($0, kAXRoleAttribute) == "AXWebArea"
        } ?? window ?? hit

        var matches: [(CGFloat, AXUIElement)] = []
        func consider(_ element: AXUIElement) {
            let role = string(element, kAXRoleAttribute) ?? ""
            guard isTextBox(element, role: role) else { return }
            guard let frame = frame(of: element) else { return }
            let boxArea = area(frame)
            guard boxArea > 80, boxArea < windowArea * 0.92 else { return }
            let expanded = frame.insetBy(dx: -8, dy: -8)
            guard expanded.contains(axPoint) || expanded.contains(cocoaPoint) else { return }
            matches.append((boxArea, element))
        }

        var budget = 0
        walk(searchRoot, budget: &budget, maxNodes: 4000) { element in
            consider(element)
        }
        if let focused = appElement(for: hit).flatMap(focusedElement(in:)) {
            consider(focused)
            for element in nearbyEditors(around: focused) {
                consider(element)
            }
        }
        for element in nearbyEditors(around: hit) {
            consider(element)
        }
        return uniqued(matches.sorted { $0.0 < $1.0 }.map(\.1))
    }

    private static func selection(fromTextBox element: AXUIElement) -> HostSelection? {
        let fileURL = sourceFileURL(from: element)
        let fileText = fileURL.flatMap(readSourceFile).map(cleanedSource)
        let axText = textInside(element)
        let source: String?
        if let fileText, looksLikeCode(fileText), looksReadable(fileText), !looksLikeWholePage(fileText) {
            source = fileText
        } else if let axText, looksReadable(axText), !looksLikeWholePage(axText), !looksLikeChrome(axText) {
            source = axText
        } else {
            source = nil
        }
        guard let source, source.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return nil }
        let hinted = fileURL?.lastPathComponent ?? fileNameHint(from: element)
        return HostSelection(
            source: source,
            fileName: isAppShell(hinted) ? nil : hinted,
            canApplyDirectly: axText != nil
        )
    }

    private static func textInside(_ element: AXUIElement) -> String? {
        if let direct = fullText(from: element).map(cleanedSource),
           direct.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
           looksReadable(direct),
           !looksLikeWholePage(direct) {
            return direct
        }
        var rows: [(CGFloat, CGFloat, String)] = []
        var budget = 0
        walk(element, budget: &budget, maxNodes: 1200) { child in
            guard !CFEqual(child, element) else { return }
            let role = string(child, kAXRoleAttribute) ?? ""
            guard role == (kAXStaticTextRole as String) || role == (kAXTextAreaRole as String) else { return }
            guard let raw = string(child, kAXValueAttribute) else { return }
            let value = cleanedSource(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 1, !looksLikeWholePage(value) else { return }
            guard let frame = frame(of: child) else { return }
            rows.append((frame.maxY, frame.minX, value))
        }
        let ordered = rows.sorted { lhs, rhs in
            if abs(lhs.0 - rhs.0) > 2 { return lhs.0 > rhs.0 }
            return lhs.1 < rhs.1
        }.map(\.2)
        guard ordered.isEmpty == false else { return nil }
        return ordered.joined(separator: "\n")
    }

    private static func looksLikeChrome(_ text: String) -> Bool {
        if text.localizedCaseInsensitiveContains("workbench.html") { return true }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3, !looksLikeCode(text) else { return false }
        let labels = lines.filter { line in
            line.split(separator: " ").count <= 4
                && !line.contains("{")
                && !line.contains("=")
                && !line.contains("(")
                && !line.contains(";")
        }
        return Double(labels.count) / Double(lines.count) > 0.65
    }

    private static func isAppShell(_ name: String?) -> Bool {
        guard let name else { return false }
        let lower = name.lowercased()
        return lower == "workbench.html" || lower == "workbench" || lower.hasPrefix("workbench.")
    }

    private static func isTextBox(_ element: AXUIElement, role: String) -> Bool {
        if role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) { return true }
        if role == "AXWebArea" || role == (kAXWindowRole as String) || role == (kAXApplicationRole as String) {
            return false
        }
        let label = (
            (string(element, kAXRoleDescriptionAttribute) ?? "") + " " + (string(element, kAXDescriptionAttribute) ?? "")
        ).lowercased()
        return label.contains("editor") || label.contains("text area") || label.contains("source editor")
    }

    private static func sourceFileURL(from element: AXUIElement) -> URL? {
        guard let url = documentURL(from: element), url.isFileURL else { return nil }
        if url.path.contains(".app/Contents/") { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 10 else { return nil }
        return url
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }

    private static func looksLikeWholePage(_ text: String) -> Bool {
        if looksLikeFileTree(text) { return true }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listings = lines.filter(isListingLine).count
        let prose = lines.filter { line in
            line.split(separator: " ").count > 8 && line.localizedCaseInsensitiveContains(" the ")
        }.count
        return listings >= 5 && prose >= 1
    }

    private static func cleanedSource(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0xFFFC || value == 0xFFFD || value == 0x2028 || value == 0x2029 {
                scalars.append("\n")
                continue
            }
            if (0xE000...0xF8FF).contains(value) || value >= 0xF0000 {
                scalars.append("\n")
                continue
            }
            if value == 0x200B || value == 0xFEFF || value == 0x2060 { continue }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func looksReadable(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.count > 500, lines.count < 4 { return false }
        if let longest = lines.map(\.count).max(), longest > 400, lines.count < 8 { return false }
        return true
    }

    private static func looksLikeFileTree(_ text: String) -> Bool {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 6 else { return false }
        let listings = lines.filter(isListingLine).count
        return Double(listings) / Double(lines.count) >= 0.35
    }

    private static func isListingLine(_ line: String) -> Bool {
        if line.contains("(") || line.contains("=") || line.contains("{") || line.contains(";") || line.contains("\"") {
            return false
        }
        if line.contains(".swift+") || line.hasPrefix("diff ") { return true }
        let token = line.split(separator: " ").last.map(String.init) ?? line
        if token.hasPrefix(".") || token.contains("/") { return true }
        let ext = (token as NSString).pathExtension
        return !ext.isEmpty && ext.count <= 8 && token.count < 96 && !token.contains(" ")
    }

    private static func fullText(from element: AXUIElement) -> String? {
        if let ranged = stringForFullRange(element), ranged.count >= 2 { return ranged }
        if let markers = stringFromMarkers(element), markers.count >= 2 { return markers }
        if let value = string(element, kAXValueAttribute), value.count >= 2 { return value }
        return nil
    }

    private static func stringForFullRange(_ element: AXUIElement) -> String? {
        let length: Int
        if let characters = intValue(element, kAXNumberOfCharactersAttribute), characters > 0 {
            length = characters
        } else if let value = string(element, kAXValueAttribute) {
            length = max(value.count, 1)
        } else {
            return nil
        }
        var range = CFRange(location: 0, length: length)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var result: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &result
        )
        guard error == .success else { return nil }
        return result as? String
    }

    private static func stringFromMarkers(_ element: AXUIElement) -> String? {
        let startNames = ["AXStartTextMarker", "AXDocumentStartMarker"]
        let endNames = ["AXEndTextMarker", "AXDocumentEndMarker"]
        for startName in startNames {
            for endName in endNames {
                var start: AnyObject?
                var end: AnyObject?
                guard AXUIElementCopyAttributeValue(element, startName as CFString, &start) == .success,
                      AXUIElementCopyAttributeValue(element, endName as CFString, &end) == .success,
                      let start, let end
                else { continue }
                var range: AnyObject?
                let markers = [start, end] as CFArray
                guard AXUIElementCopyParameterizedAttributeValue(
                    element,
                    "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                    markers,
                    &range
                ) == .success, let range else { continue }
                var text: AnyObject?
                guard AXUIElementCopyParameterizedAttributeValue(
                    element,
                    "AXStringForTextMarkerRange" as CFString,
                    range,
                    &text
                ) == .success else { continue }
                if let string = text as? String, !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private static func documentURL(from element: AXUIElement) -> URL? {
        for node in ancestors(of: element, limit: 12) {
            if let url = urlValue(node, kAXDocumentAttribute) { return url }
            if let url = urlValue(node, kAXURLAttribute) { return url }
            if let url = urlValue(node, "AXFilename") { return url }
        }
        return nil
    }

    private static func fileNameHint(from element: AXUIElement) -> String? {
        if let url = documentURL(from: element) { return url.lastPathComponent }
        for node in ancestors(of: element, limit: 12) {
            let role = string(node, kAXRoleAttribute)
            if role == (kAXWindowRole as String) || role == (kAXApplicationRole as String) {
                if let title = string(node, kAXTitleAttribute), let name = fileName(fromWindowTitle: title) {
                    return name
                }
            }
        }
        return nil
    }

    private static func fileName(fromWindowTitle title: String) -> String? {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("●") || trimmed.hasPrefix("*") {
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }
        let part = trimmed
            .components(separatedBy: " — ")
            .first?
            .components(separatedBy: " - ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        let name = (part as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 10, name.count > ext.count + 1 else { return nil }
        return name
    }

    private static func readSourceFile(_ url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= 2_000_000
        else { return nil }
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.contains("\0") {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1), !text.contains("\0") {
            return text
        }
        return nil
    }

    private static func nearbyEditors(around element: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        if let parentElement = parent(of: element) {
            found.append(contentsOf: children(of: parentElement).prefix(40))
            if let grand = parent(of: parentElement) {
                found.append(contentsOf: children(of: grand).prefix(40))
            }
        }
        found.append(contentsOf: children(of: element).prefix(40))
        return found
    }

    private static func editors(in app: AXUIElement, intersecting region: CGRect) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        var visited = 0
        walk(app, budget: &visited, maxNodes: 1800) { element in
            guard let frame = frame(of: element), frame.intersects(region) else { return }
            let role = string(element, kAXRoleAttribute) ?? ""
            if editorRoles.contains(role) || string(element, kAXValueAttribute)?.contains("\n") == true {
                matches.append(element)
            }
        }
        return matches
    }

    private static func walk(_ element: AXUIElement, budget: inout Int, maxNodes: Int, visit: (AXUIElement) -> Void) {
        guard budget < maxNodes else { return }
        budget += 1
        visit(element)
        let role = string(element, kAXRoleAttribute) ?? ""
        if ignoredRoles.contains(role) { return }
        for child in children(of: element) {
            walk(child, budget: &budget, maxNodes: maxNodes, visit: visit)
        }
    }

    private static func element(atCocoa point: CGPoint) -> AXUIElement? {
        element(atAX: axPoint(fromCocoa: point))
    }

    private static func element(atCocoaFlipped point: CGPoint) -> AXUIElement? {
        element(atAX: point)
    }

    private static func element(atAX point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        guard error == .success else { return nil }
        return hit
    }

    private static func application(atCocoa point: CGPoint) -> AXUIElement? {
        guard let hit = element(atCocoa: point) ?? element(atCocoaFlipped: point) else {
            return frontmostAppElement()
        }
        return ancestors(of: hit, limit: 20).first { string($0, kAXRoleAttribute) == (kAXApplicationRole as String) }
            ?? appElement(for: hit)
            ?? frontmostAppElement()
    }

    private static func appElement(for element: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static func frontmostAppElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static func focusedElement(in app: AXUIElement) -> AXUIElement? {
        copyElement(app, kAXFocusedUIElementAttribute)
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        copyElement(app, kAXFocusedWindowAttribute)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        copyElement(element, kAXParentAttribute as String)
    }

    private static func ancestors(of element: AXUIElement, limit: Int) -> [AXUIElement] {
        var items: [AXUIElement] = [element]
        var current = element
        for _ in 0..<limit {
            guard let next = parent(of: current), !CFEqual(current, next) else { break }
            items.append(next)
            current = next
        }
        return items
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject]
        else { return [] }
        return array.map { $0 as! AXUIElement }
    }

    private static func uniqued(_ elements: [AXUIElement]) -> [AXUIElement] {
        var unique: [AXUIElement] = []
        for element in elements where !unique.contains(where: { CFEqual($0, element) }) {
            unique.append(element)
        }
        return unique
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func intValue(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private static func urlValue(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        if let url = value as? URL { return url }
        if let string = value as? String {
            if string.hasPrefix("file:"), let url = URL(string: string) { return url }
            if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionRef = positionValue,
              let sizeRef = sizeValue
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        let positionAX = positionRef as! AXValue
        let sizeAX = sizeRef as! AXValue
        guard AXValueGetValue(positionAX, .cgPoint, &origin),
              AXValueGetValue(sizeAX, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axPoint(fromCocoa point: CGPoint) -> CGPoint {
        let top = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? point.y
        return CGPoint(x: point.x, y: top - point.y)
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let hints = [
            "func ", "class ", "struct ", "import ", "export ", "def ", "const ", "let ", "var ",
            "fn ", "#include", "package ", "return ", "=>"
        ]
        return hints.contains(where: text.contains)
    }

    private static let editorRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        "AXWebArea",
        kAXGroupRole as String
    ]

    private static let ignoredRoles: Set<String> = [
        kAXMenuRole as String,
        kAXMenuBarRole as String,
        kAXMenuItemRole as String,
        kAXButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXToolbarRole as String,
        kAXScrollBarRole as String,
        kAXSplitterRole as String,
        kAXImageRole as String,
        kAXOutlineRole as String,
        kAXTableRole as String,
        kAXTabGroupRole as String
    ]
}
