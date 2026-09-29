import Foundation

public struct ExplanationTerm: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var meaning: String

    public init(name: String, meaning: String) {
        self.name = name
        self.meaning = meaning
    }
}

public struct ExplanationSection: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var plainEnglish: String
    public var startLine: Int
    public var endLine: Int
    public var terms: [ExplanationTerm]

    public init(
        id: UUID = UUID(),
        title: String,
        plainEnglish: String,
        startLine: Int,
        endLine: Int,
        terms: [ExplanationTerm] = []
    ) {
        self.id = id
        self.title = title
        self.plainEnglish = plainEnglish
        self.startLine = max(1, startLine)
        self.endLine = max(self.startLine, endLine)
        self.terms = terms
    }

    public var lineRange: ClosedRange<Int> {
        startLine...endLine
    }
}

public struct LineExplanation: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int { line }
    public var line: Int
    public var meaning: String

    public init(line: Int, meaning: String) {
        self.line = max(1, line)
        self.meaning = meaning
    }
}

public struct Explanation: Codable, Sendable, Equatable {
    public var overview: String
    public var sections: [ExplanationSection]
    public var lineMeanings: [LineExplanation]
    public var language: DetectedLanguage
    public var depth: ExplanationDepth

    public init(
        overview: String,
        sections: [ExplanationSection] = [],
        lineMeanings: [LineExplanation] = [],
        language: DetectedLanguage,
        depth: ExplanationDepth
    ) {
        self.overview = overview
        self.sections = sections
        self.lineMeanings = lineMeanings
        self.language = language
        self.depth = depth
    }

    public func meaning(forLine number: Int) -> String? {
        lineMeanings.first { $0.line == number }?.meaning
    }

    enum CodingKeys: String, CodingKey {
        case overview, sections, lineMeanings, language, depth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        sections = try container.decodeIfPresent([ExplanationSection].self, forKey: .sections) ?? []
        lineMeanings = try container.decodeIfPresent([LineExplanation].self, forKey: .lineMeanings) ?? []
        language = try container.decode(DetectedLanguage.self, forKey: .language)
        depth = try container.decodeIfPresent(ExplanationDepth.self, forKey: .depth) ?? .simple
    }
}
