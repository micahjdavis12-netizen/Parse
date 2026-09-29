import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(macOS 26.0, *)
actor FoundationWarmStart {
    static let shared = FoundationWarmStart()
    private var session: LanguageModelSession?

    func prewarm() {
        guard SystemLanguageModel.default.isAvailable else { return }
        if session == nil {
            session = LanguageModelSession(instructions: TranslationPrompts.systemPersona)
        }
        session?.prewarm()
    }

    func makeSession() -> LanguageModelSession {
        if let existing = session {
            session = nil
            return existing
        }
        return LanguageModelSession(instructions: TranslationPrompts.systemPersona)
    }
}
#endif

public struct UnavailableOnDeviceProvider: ModelProvider {
    public var displayName: String { "On-device" }
    public var isAvailable: Bool { false }
    public var isCloud: Bool { false }

    public init() {}

    public func explain(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation {
        throw ParseError.modelUnavailable
    }

    public func refineExplanation(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) async throws -> Explanation {
        throw ParseError.modelUnavailable
    }

    public func proposeChange(request: EditRequest) async throws -> (proposedSource: String, whatChangedEnglish: String) {
        throw ParseError.modelUnavailable
    }
}

public struct AppleFoundationProvider: ModelProvider {
    public var displayName: String { "On-device" }
    public var isCloud: Bool { false }

    public init() {}

    public static func prewarmIfPossible() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            Task {
                await FoundationWarmStart.shared.prewarm()
            }
        }
        #endif
    }

    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    public func refineLanguage(code: String, heuristic: DetectedLanguage) async throws -> DetectedLanguage {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let request = TranslationPrompts.refineLanguage(code: code, heuristic: heuristic)
            let raw = try await completeText(request)
            let dto = try JSONValueParser.decode(LanguageDTO.self, from: raw)
            return dto.asLanguage(fallback: heuristic)
        }
        #endif
        return heuristic
    }

    public func explain(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await explainWithFoundationModels(snippet: snippet, depth: depth)
        }
        #endif
        throw ParseError.modelUnavailable
    }

    public func refineExplanation(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) async throws -> Explanation {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await refineWithFoundationModels(snippet: snippet, draft: draft, depth: depth)
        }
        #endif
        throw ParseError.modelUnavailable
    }

    public func proposeChange(request: EditRequest) async throws -> (proposedSource: String, whatChangedEnglish: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await proposeWithFoundationModels(request)
        }
        #endif
        throw ParseError.modelUnavailable
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func explainWithFoundationModels(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation {
        let generated = try await generate(ExplanationGenerated.self, request: TranslationPrompts.explain(snippet: snippet, depth: depth))
        return generated.asExplanation(language: snippet.language, depth: depth)
    }

    @available(macOS 26.0, *)
    private func refineWithFoundationModels(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) async throws -> Explanation {
        let generated = try await generate(
            ExplanationGenerated.self,
            request: TranslationPrompts.cohere(snippet: snippet, draft: draft, depth: depth)
        )
        return generated.asExplanation(language: snippet.language, depth: depth)
    }

    @available(macOS 26.0, *)
    private func proposeWithFoundationModels(_ request: EditRequest) async throws -> (proposedSource: String, whatChangedEnglish: String) {
        let generated = try await generate(ChangeGenerated.self, request: TranslationPrompts.change(request: request))
        return (generated.proposedSource, generated.whatChangedEnglish)
    }

    @available(macOS 26.0, *)
    private func completeText(_ request: GenerationRequest) async throws -> String {
        try ensureAvailable()
        let session = await FoundationWarmStart.shared.makeSession()
        let response = try await session.respond(to: "\(request.system)\n\n\(request.prompt)")
        return response.content
    }

    @available(macOS 26.0, *)
    private func generate<T: Generable>(_ type: T.Type, request: GenerationRequest) async throws -> T {
        try ensureAvailable()
        let session = await FoundationWarmStart.shared.makeSession()
        let response = try await session.respond(to: "\(request.system)\n\n\(request.prompt)", generating: type)
        return response.content
    }

    @available(macOS 26.0, *)
    private func ensureAvailable() throws {
        guard SystemLanguageModel.default.isAvailable else {
            throw ParseError.modelUnavailable
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct ExplanationGenerated {
    var overview: String
    var lines: [LineGenerated]

    func asExplanation(language: DetectedLanguage, depth: ExplanationDepth) -> Explanation {
        Explanation(
            overview: overview,
            lineMeanings: lines.map { LineExplanation(line: $0.line, meaning: $0.meaning) },
            language: language,
            depth: depth
        )
    }
}

@available(macOS 26.0, *)
@Generable
struct LineGenerated {
    var line: Int
    var meaning: String
}

@available(macOS 26.0, *)
@Generable
struct ChangeGenerated {
    var proposedSource: String
    var whatChangedEnglish: String
}
#endif
