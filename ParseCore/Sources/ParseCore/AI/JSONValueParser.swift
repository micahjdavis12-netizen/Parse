import Foundation

struct JSONValueParser {
    static func data(from raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = extractJSONObject(trimmed).data(using: .utf8) {
            return data
        }
        throw ParseError.invalidResponse("The model did not return JSON.")
    }

    static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let data = try data(from: raw)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ParseError.invalidResponse("Could not read the model response.")
        }
    }

    private static func extractJSONObject(_ raw: String) -> String {
        if let fenced = raw.range(of: #"```(?:json)?\s*([\s\S]*?)```"#, options: .regularExpression) {
            let inner = String(raw[fenced])
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.hasPrefix("{") { return inner }
        }
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            return String(raw[start...end])
        }
        return raw
    }
}

struct ExplanationDTO: Codable {
    var overview: String
    var sections: [SectionDTO]?
    var lines: [LineDTO]?

    struct SectionDTO: Codable {
        var title: String
        var plainEnglish: String
        var startLine: Int
        var endLine: Int
        var terms: [TermDTO]?
    }

    struct TermDTO: Codable {
        var name: String
        var meaning: String
    }

    struct LineDTO: Codable {
        var line: Int
        var meaning: String
    }

    func asExplanation(language: DetectedLanguage, depth: ExplanationDepth) -> Explanation {
        Explanation(
            overview: overview,
            sections: (sections ?? []).map { section in
                ExplanationSection(
                    title: section.title,
                    plainEnglish: section.plainEnglish,
                    startLine: section.startLine,
                    endLine: section.endLine,
                    terms: (section.terms ?? []).map { ExplanationTerm(name: $0.name, meaning: $0.meaning) }
                )
            },
            lineMeanings: (lines ?? []).map { LineExplanation(line: $0.line, meaning: $0.meaning) },
            language: language,
            depth: depth
        )
    }
}

struct ChangeDTO: Codable {
    var proposedSource: String
    var whatChangedEnglish: String
}

struct LanguageDTO: Codable {
    var name: String
    var identifier: String?
    var confidence: String?
    var alternatives: [String]?

    func asLanguage(fallback: DetectedLanguage) -> DetectedLanguage {
        let confidenceValue: LanguageConfidence = switch (confidence ?? "").lowercased() {
        case "high": .high
        case "medium": .medium
        default: .low
        }
        return DetectedLanguage(
            name: name.isEmpty ? fallback.name : name,
            identifier: identifier ?? fallback.identifier,
            confidence: confidenceValue,
            alternatives: alternatives ?? [],
            wasDetectedAutomatically: true
        )
    }
}
