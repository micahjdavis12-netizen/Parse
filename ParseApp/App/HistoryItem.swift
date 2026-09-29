import Foundation
import ParseCore

struct HistoryItem: Identifiable, Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var source: String
    var fileName: String?
    var language: DetectedLanguage
    var surrounding: String?
    var explanation: Explanation?
    var depth: ExplanationDepth
    var instruction: String
    var proposedSource: String?
    var whatChangedEnglish: String?
    var usedCloud: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        source: String,
        fileName: String? = nil,
        language: DetectedLanguage,
        surrounding: String? = nil,
        explanation: Explanation? = nil,
        depth: ExplanationDepth = .simple,
        instruction: String = "",
        proposedSource: String? = nil,
        whatChangedEnglish: String? = nil,
        usedCloud: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.source = source
        self.fileName = fileName
        self.language = language
        self.surrounding = surrounding
        self.explanation = explanation
        self.depth = depth
        self.instruction = instruction
        self.proposedSource = proposedSource
        self.whatChangedEnglish = whatChangedEnglish
        self.usedCloud = usedCloud
    }

    var preview: String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(2)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(fileName: String?, language: DetectedLanguage, source: String) -> String {
        if let fileName, !fileName.isEmpty { return fileName }
        let first = source.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if first.count > 42 {
            return String(first.prefix(40)) + "…"
        }
        if first.isEmpty {
            return "\(language.name) snippet"
        }
        return first
    }
}
