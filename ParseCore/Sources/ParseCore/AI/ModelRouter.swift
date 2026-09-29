import Foundation

public struct ModelRouter: Sendable {
    public var largeLineThreshold: Int
    public var cloudAvailable: Bool
    public var onDeviceAvailable: Bool

    public init(largeLineThreshold: Int = 200, cloudAvailable: Bool, onDeviceAvailable: Bool) {
        self.largeLineThreshold = largeLineThreshold
        self.cloudAvailable = cloudAvailable
        self.onDeviceAvailable = onDeviceAvailable
    }

    public func decision(for job: TranslationJob) -> RouteDecision {
        let isLarge = job.isLarge(threshold: largeLineThreshold)

        if isLarge, cloudAvailable {
            return RouteDecision(
                route: .cloud,
                isLargeChange: true,
                reason: "Large change routed to the cloud model.",
                showCloudHint: false
            )
        }

        if onDeviceAvailable {
            return RouteDecision(
                route: .onDevice,
                isLargeChange: isLarge,
                reason: isLarge ? "Large change staying on-device because no API key is set." : "On-device model.",
                showCloudHint: isLarge && !cloudAvailable
            )
        }

        if cloudAvailable {
            return RouteDecision(
                route: .cloud,
                isLargeChange: isLarge,
                reason: "On-device model unavailable; using the API key.",
                showCloudHint: false
            )
        }

        return RouteDecision(
            route: .onDevice,
            isLargeChange: isLarge,
            reason: "No model is available.",
            showCloudHint: false
        )
    }
}

public struct TranslationJob: Sendable {
    public var kind: Kind
    public var snippet: CodeSnippet
    public var instruction: String?
    public var explanation: Explanation?
    public var isRetry: Bool

    public enum Kind: Sendable {
        case explain
        case edit
    }

    public init(
        kind: Kind,
        snippet: CodeSnippet,
        instruction: String? = nil,
        explanation: Explanation? = nil,
        isRetry: Bool = false
    ) {
        self.kind = kind
        self.snippet = snippet
        self.instruction = instruction
        self.explanation = explanation
        self.isRetry = isRetry
    }

    public func isLarge(threshold: Int) -> Bool {
        if kind == .explain { return false }
        if isRetry { return true }
        if snippet.lineCount > threshold { return true }
        if let surrounding = snippet.surrounding {
            let surroundingLines = surrounding.split(separator: "\n", omittingEmptySubsequences: false).count
            if snippet.lineCount + surroundingLines > threshold + 60 { return true }
        }
        if let instruction, looksLikeBroadRewrite(instruction) { return true }
        if let explanation, explanation.sections.count >= 6, instruction?.isEmpty == false {
            return true
        }
        return false
    }

    private func looksLikeBroadRewrite(_ instruction: String) -> Bool {
        let lowered = instruction.lowercased()
        let markers = [
            "rewrite", "across", "entire file", "whole file", "all of this",
            "authentication", "new feature", "refactor", "every function"
        ]
        return markers.contains { lowered.contains($0) }
    }
}
