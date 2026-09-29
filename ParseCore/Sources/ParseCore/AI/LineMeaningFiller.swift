import Foundation

public enum LineMeaningFiller {
    public static func fill(source: String, explanation: Explanation) -> Explanation {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let provided = Dictionary(
            explanation.lineMeanings.map { ($0.line, $0.meaning) },
            uniquingKeysWith: { _, latest in latest }
        )
        var filled: [LineExplanation] = []
        var soFar: [Int: String] = [:]

        for (index, line) in lines.enumerated() {
            let number = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let meaning = provided[number]?.trimmingCharacters(in: .whitespacesAndNewlines), !meaning.isEmpty {
                filled.append(LineExplanation(line: number, meaning: meaning))
                soFar[number] = meaning
                continue
            }

            let meaning = fallback(
                for: String(line),
                number: number,
                previous: nearestMeaning(before: number, in: soFar),
                next: nearestMeaning(after: number, in: provided),
                explanation: explanation
            )
            filled.append(LineExplanation(line: number, meaning: meaning))
            soFar[number] = meaning
        }

        var copy = explanation
        copy.lineMeanings = filled
        return copy
    }

    public static func merging(source: String, draft: Explanation, refined: Explanation) -> Explanation {
        let draftMap = Dictionary(
            draft.lineMeanings.map { ($0.line, $0.meaning) },
            uniquingKeysWith: { _, latest in latest }
        )
        let refinedMap = Dictionary(
            refined.lineMeanings.map { ($0.line, $0.meaning) },
            uniquingKeysWith: { _, latest in latest }
        )
        var combined = draft
        let overview = refined.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty {
            combined.overview = overview
        }
        combined.lineMeanings = Set(draftMap.keys).union(refinedMap.keys).sorted().compactMap { number in
            let refinedText = refinedMap[number]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !refinedText.isEmpty {
                return LineExplanation(line: number, meaning: refinedText)
            }
            let draftText = draftMap[number]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !draftText.isEmpty {
                return LineExplanation(line: number, meaning: draftText)
            }
            return nil
        }
        if refined.sections.isEmpty == false {
            combined.sections = refined.sections
        }
        return fill(source: source, explanation: combined)
    }

    private static func nearestMeaning(before number: Int, in meanings: [Int: String]) -> String? {
        meanings.keys.filter { $0 < number }.sorted().last.flatMap { key in
            let text = meanings[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }

    private static func nearestMeaning(after number: Int, in meanings: [Int: String]) -> String? {
        meanings.keys.filter { $0 > number }.sorted().first.flatMap { key in
            let text = meanings[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }

    private static func fallback(
        for line: String,
        number: Int,
        previous: String?,
        next: String?,
        explanation: Explanation
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = identifiers(in: trimmed)

        if trimmed == "{" || trimmed.hasSuffix("{") {
            if let next, !isGenerated(next) { return "This opens the work that \(lowercaseFirst(clip(next)))" }
            if !named.isEmpty { return "This opens \(named.joined(separator: ", "))." }
            return "This opens the block."
        }
        if trimmed == "}" || trimmed == "}," || trimmed == "};" || trimmed == ")" || trimmed == "]," {
            if let previous, !isGenerated(previous) { return "This finishes \(lowercaseFirst(clip(previous)))" }
            return "This closes the block."
        }
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
            return "A note in the code: \(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/#* ")))."
        }
        if let literal = quotedText(trimmed) {
            return "The value \(literal)."
        }

        let focus = named.isEmpty ? trimmed : named.joined(separator: ", ")
        let sentence = named.isEmpty ? "This line is \(focus)." : "This uses \(focus)."
        if let next, !isGenerated(next) {
            return "\(sentence) Next: \(clip(next))"
        }
        if let section = explanation.sections.first(where: { $0.lineRange.contains(number) }) {
            return "Line \(number) is part of \(section.title.lowercased()). \(firstSentence(section.plainEnglish))"
        }
        if !explanation.overview.isEmpty, named.isEmpty {
            return "In this snippet — \(firstSentence(explanation.overview)) — \(lowercaseFirst(sentence))"
        }
        return sentence
    }

    private static func quotedText(_ line: String) -> String? {
        let core = line.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        guard core.count >= 2, let first = core.first, core.last == first else { return nil }
        guard first == "'" || first == "\"" || first == "`" else { return nil }
        return core
    }

    private static func isGenerated(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prefixes = [
            "after ", "this uses ", "this opens ", "this closes ", "this finishes ",
            "this starts ", "the value ", "a note in the code", "this line is "
        ]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    private static func identifiers(in line: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = pattern?.matches(in: line, range: range) ?? []
        var seen: Set<String> = []
        var names: [String] = []
        for match in matches {
            guard let span = Range(match.range, in: line) else { continue }
            let token = String(line[span])
            if ignoredTokens.contains(token.lowercased()) { continue }
            if seen.contains(token) { continue }
            seen.insert(token)
            names.append(token)
            if names.count == 4 { break }
        }
        return names
    }

    private static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 110 { return trimmed }
        return String(trimmed.prefix(107)) + "…"
    }

    private static func lowercaseFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            return String(trimmed[...end])
        }
        if trimmed.count > 140 {
            return String(trimmed.prefix(137)) + "…"
        }
        return trimmed
    }

    private static let ignoredTokens: Set<String> = [
        "func", "function", "def", "fn", "let", "var", "const", "if", "else", "elif",
        "return", "import", "from", "class", "struct", "enum", "protocol", "extension",
        "for", "while", "switch", "case", "break", "continue", "true", "false", "nil",
        "null", "none", "self", "this", "super", "public", "private", "internal",
        "static", "void", "int", "string", "bool", "boolean", "number", "async", "await",
        "try", "catch", "throw", "guard", "in", "of", "as", "is", "new", "type",
        "print", "console", "log", "where", "when", "do", "then", "and", "or", "not"
    ]
}
