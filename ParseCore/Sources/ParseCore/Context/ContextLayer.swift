import Foundation

public enum ContextLayer {
    public static func snippet(
        from selection: HostSelection,
        context: CodeContext,
        language: DetectedLanguage
    ) -> CodeSnippet {
        CodeSnippet(
            source: selection.source,
            fileName: selection.fileName,
            language: language,
            surrounding: context.surrounding
        )
    }

    public static func isLarge(_ snippet: CodeSnippet, context: CodeContext = .empty) -> Bool {
        let sourceLines = snippet.lineCount
        let surroundingLines: Int = {
            guard let surrounding = context.surrounding ?? snippet.surrounding, !surrounding.isEmpty else { return 0 }
            return surrounding.split(separator: "\n", omittingEmptySubsequences: false).count
        }()
        return sourceLines > 200 || (sourceLines + surroundingLines) > 260
    }
}
