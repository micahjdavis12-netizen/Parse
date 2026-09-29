import Foundation

public struct LineIntent: Codable, Sendable, Equatable {
    public var line: Int
    public var source: String
    public var english: String
    public var originalEnglish: String

    public init(line: Int, source: String, english: String, originalEnglish: String = "") {
        self.line = line
        self.source = source
        self.english = english
        self.originalEnglish = originalEnglish
    }

    public var didChange: Bool {
        english.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct EditRequest: Codable, Sendable, Equatable {
    public var instruction: String
    public var snippet: CodeSnippet
    public var explanation: Explanation?
    public var lineIntents: [LineIntent]
    public var isRetry: Bool

    public init(
        instruction: String,
        snippet: CodeSnippet,
        explanation: Explanation? = nil,
        lineIntents: [LineIntent] = [],
        isRetry: Bool = false
    ) {
        self.instruction = instruction
        self.snippet = snippet
        self.explanation = explanation
        self.lineIntents = lineIntents
        self.isRetry = isRetry
    }
}

public struct GenerationRequest: Sendable {
    public var prompt: String
    public var system: String
    public var jsonMode: Bool

    public init(prompt: String, system: String, jsonMode: Bool = true) {
        self.prompt = prompt
        self.system = system
        self.jsonMode = jsonMode
    }
}

public enum ModelRoute: String, Sendable, Equatable {
    case onDevice
    case cloud
}

public struct RouteDecision: Sendable, Equatable {
    public var route: ModelRoute
    public var isLargeChange: Bool
    public var reason: String
    public var showCloudHint: Bool

    public init(route: ModelRoute, isLargeChange: Bool, reason: String, showCloudHint: Bool) {
        self.route = route
        self.isLargeChange = isLargeChange
        self.reason = reason
        self.showCloudHint = showCloudHint
    }
}
