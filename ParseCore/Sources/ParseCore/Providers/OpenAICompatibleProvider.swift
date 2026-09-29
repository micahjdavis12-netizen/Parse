import Foundation

public struct CloudProviderConfiguration: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case openai
        case anthropic
        case custom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .openai: "OpenAI"
            case .anthropic: "Anthropic"
            case .custom: "Custom"
            }
        }
    }

    public var kind: Kind
    public var apiKey: String
    public var baseURL: String
    public var model: String

    public init(kind: Kind = .openai, apiKey: String = "", baseURL: String = "", model: String = "") {
        self.kind = kind
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var resolvedBaseURL: URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .openai:
            return URL(string: trimmed.isEmpty ? "https://api.openai.com/v1" : trimmed) ?? URL(string: "https://api.openai.com/v1")!
        case .anthropic:
            return URL(string: trimmed.isEmpty ? "https://api.anthropic.com" : trimmed) ?? URL(string: "https://api.anthropic.com")!
        case .custom:
            return URL(string: trimmed.isEmpty ? "https://api.openai.com/v1" : trimmed) ?? URL(string: "https://api.openai.com/v1")!
        }
    }

    public var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch kind {
        case .openai, .custom: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }
}

public struct OpenAICompatibleProvider: ModelProvider {
    public var configuration: CloudProviderConfiguration
    public var session: URLSession
    public var displayName: String
    public var isCloud: Bool { true }

    public init(configuration: CloudProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.displayName = configuration.kind.title
    }

    public var isAvailable: Bool {
        configuration.isConfigured
    }

    public func refineLanguage(code: String, heuristic: DetectedLanguage) async throws -> DetectedLanguage {
        let request = TranslationPrompts.refineLanguage(code: code, heuristic: heuristic)
        let raw = try await complete(request)
        let dto = try JSONValueParser.decode(LanguageDTO.self, from: raw)
        return dto.asLanguage(fallback: heuristic)
    }

    public func explain(snippet: CodeSnippet, depth: ExplanationDepth) async throws -> Explanation {
        let request = TranslationPrompts.explain(snippet: snippet, depth: depth)
        let raw = try await complete(request)
        let dto = try JSONValueParser.decode(ExplanationDTO.self, from: raw)
        return dto.asExplanation(language: snippet.language, depth: depth)
    }

    public func refineExplanation(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) async throws -> Explanation {
        let request = TranslationPrompts.cohere(snippet: snippet, draft: draft, depth: depth)
        let raw = try await complete(request)
        let dto = try JSONValueParser.decode(ExplanationDTO.self, from: raw)
        var explanation = dto.asExplanation(language: snippet.language, depth: depth)
        if explanation.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            explanation.overview = draft.overview
        }
        return explanation
    }

    public func proposeChange(request: EditRequest) async throws -> (proposedSource: String, whatChangedEnglish: String) {
        let generation = TranslationPrompts.change(request: request)
        let raw = try await complete(generation)
        let dto = try JSONValueParser.decode(ChangeDTO.self, from: raw)
        return (dto.proposedSource, dto.whatChangedEnglish)
    }

    public func testConnection() async throws -> String {
        let ping = GenerationRequest(
            prompt: "Reply with the single word pong.",
            system: "You are a connection test. Reply with pong.",
            jsonMode: false
        )
        let raw = try await complete(ping)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func complete(_ request: GenerationRequest) async throws -> String {
        guard isAvailable else { throw ParseError.modelUnavailable }
        switch configuration.kind {
        case .openai, .custom:
            return try await completeOpenAI(request)
        case .anthropic:
            return try await completeAnthropic(request)
        }
    }

    private func completeOpenAI(_ request: GenerationRequest) async throws -> String {
        var url = configuration.resolvedBaseURL
        if url.path.isEmpty || url.path == "/" {
            url.append(path: "chat/completions")
        } else if !url.path.contains("chat/completions") {
            url.append(path: "chat/completions")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": configuration.resolvedModel,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.prompt]
            ],
            "temperature": 0.2
        ]
        if request.jsonMode {
            payload["response_format"] = ["type": "json_object"]
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: urlRequest)
        try throwIfNeeded(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw ParseError.invalidResponse("The cloud model returned an empty reply.")
        }
        return content
    }

    private func completeAnthropic(_ request: GenerationRequest) async throws -> String {
        var url = configuration.resolvedBaseURL
        if url.path.isEmpty || url.path == "/" {
            url.append(path: "v1/messages")
        } else if !url.path.contains("messages") {
            url.append(path: "v1/messages")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": configuration.resolvedModel,
            "max_tokens": 4096,
            "system": request.system,
            "messages": [
                ["role": "user", "content": request.prompt]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: urlRequest)
        try throwIfNeeded(response: response, data: data)
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = decoded.content.compactMap(\.text).joined()
        guard !content.isEmpty else {
            throw ParseError.invalidResponse("The cloud model returned an empty reply.")
        }
        return content
    }

    private func throwIfNeeded(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ParseError.network("Cloud request failed (\(http.statusCode)). \(body.prefix(240))")
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        var text: String?
    }
    var content: [Content]
}
