import Foundation

public struct CodeSnippet: Codable, Sendable, Equatable {
    public var source: String
    public var fileName: String?
    public var language: DetectedLanguage
    public var surrounding: String?

    public init(
        source: String,
        fileName: String? = nil,
        language: DetectedLanguage = .unknown,
        surrounding: String? = nil
    ) {
        self.source = source
        self.fileName = fileName
        self.language = language
        self.surrounding = surrounding
    }

    public var lineCount: Int {
        if source.isEmpty { return 0 }
        return source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    public var lines: [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
