import Foundation

public struct TranslationEngine: Sendable {
    public var onDevice: any ModelProvider
    public var cloud: (any ModelProvider)?
    public var router: ModelRouter

    public init(onDevice: any ModelProvider, cloud: (any ModelProvider)?, router: ModelRouter) {
        self.onDevice = onDevice
        self.cloud = cloud
        self.router = router
    }

    public var anyProviderAvailable: Bool {
        onDevice.isAvailable || (cloud?.isAvailable ?? false)
    }

    public func detectLanguage(code: String, fileName: String?, hint: String?) -> DetectedLanguage {
        LanguageDetector.detect(code: code, fileName: fileName, hint: hint)
    }

    public func explain(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation {
        let provider = try provider(for: TranslationJob(kind: .explain, snippet: snippet))
        do {
            return try await completeExplanation(snippet: snippet, depth: depth, provider: provider)
        } catch {
            guard ParseError.isContextLimit(error), let cloud, cloud.isAvailable, !provider.isCloud else {
                throw error
            }
            return try await completeExplanation(snippet: snippet, depth: depth, provider: cloud)
        }
    }

    private func completeExplanation(
        snippet: CodeSnippet,
        depth: ExplanationDepth,
        provider: any ModelProvider
    ) async throws -> Explanation {
        var explanation = try await provider.explain(snippet: snippet, depth: depth)
        explanation.language = snippet.language
        explanation.depth = depth
        explanation.sections = explanation.sections.map { section in
            var copy = section
            copy.title = SectionTitle.normalize(section.title)
            copy.startLine = min(max(1, section.startLine), max(1, snippet.lineCount))
            copy.endLine = min(max(copy.startLine, section.endLine), max(copy.startLine, snippet.lineCount))
            return copy
        }
        let draft = LineMeaningFiller.fill(source: snippet.source, explanation: explanation)
        guard draft.lineMeanings.count >= 2 else { return draft }
        do {
            let refined = try await provider.refineExplanation(snippet: snippet, draft: draft, depth: depth)
            var merged = LineMeaningFiller.merging(source: snippet.source, draft: draft, refined: refined)
            merged.language = snippet.language
            merged.depth = depth
            return merged
        } catch {
            return draft
        }
    }

    public func propose(request: EditRequest) async throws -> (change: ProposedChange, decision: RouteDecision) {
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLineIntents = request.lineIntents.contains {
            !$0.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !instruction.isEmpty || hasLineIntents else { throw ParseError.emptyInstruction }
        guard !request.snippet.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.emptyCode
        }

        let changedEnglish = request.lineIntents
            .filter(\.didChange)
            .map(\.english)
            .joined(separator: "\n")
        let jobInstruction = [instruction, changedEnglish]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let job = TranslationJob(
            kind: .edit,
            snippet: request.snippet,
            instruction: jobInstruction,
            explanation: request.explanation,
            isRetry: request.isRetry
        )
        let decision = router.decision(for: job)
        let provider = try provider(for: job, decision: decision)
        let raw = try await provider.proposeChange(request: request)
        let flags = SafetyClassifier.classify(
            original: request.snippet.source,
            proposed: raw.proposedSource,
            instruction: jobInstruction
        )
        let change = ChangeEngine.proposedChange(
            original: request.snippet.source,
            proposed: raw.proposedSource,
            whatChangedEnglish: raw.whatChangedEnglish,
            safetyFlags: flags,
            usedCloud: provider.isCloud,
            providerName: provider.displayName
        )
        return (change, decision)
    }

    public func provider(for job: TranslationJob) throws -> any ModelProvider {
        try provider(for: job, decision: router.decision(for: job))
    }

    private func provider(for _: TranslationJob, decision: RouteDecision) throws -> any ModelProvider {
        switch decision.route {
        case .cloud:
            if let cloud, cloud.isAvailable { return cloud }
            if onDevice.isAvailable { return onDevice }
            throw ParseError.modelUnavailable
        case .onDevice:
            if onDevice.isAvailable { return onDevice }
            if let cloud, cloud.isAvailable { return cloud }
            throw ParseError.modelUnavailable
        }
    }
}
