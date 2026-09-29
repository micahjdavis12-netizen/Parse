import Foundation

public enum ParseError: Error, Sendable, Equatable, LocalizedError {
    case modelUnavailable
    case emptyCode
    case emptyInstruction
    case invalidResponse(String)
    case network(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is unavailable, and no API key is set for larger edits."
        case .emptyCode:
            "Paste or select some code first."
        case .emptyInstruction:
            "Describe the new behavior in English for at least one line."
        case .invalidResponse(let message):
            message
        case .network(let message):
            message
        case .cancelled:
            "Cancelled."
        }
    }

    public static func isContextLimit(_ error: Error) -> Bool {
        isContextLimitMessage(error.localizedDescription)
    }

    public static func isContextLimitMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("context")
    }
}

public protocol ModelProvider: Sendable {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var isCloud: Bool { get }

    func refineLanguage(code: String, heuristic: DetectedLanguage) async throws -> DetectedLanguage
    func explain(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation
    func refineExplanation(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) async throws -> Explanation
    func proposeChange(request: EditRequest) async throws -> (proposedSource: String, whatChangedEnglish: String)
}

public extension ModelProvider {
    func refineLanguage(code: String, heuristic: DetectedLanguage) async throws -> DetectedLanguage {
        heuristic
    }
}
