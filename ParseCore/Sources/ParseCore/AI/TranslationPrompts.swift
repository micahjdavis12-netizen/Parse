import Foundation

public enum TranslationPrompts {
    public static var systemPersona: String {
        """
        You are Parse, a translation layer between humans and code.
        You explain what code does in natural language and produce the smallest code change that matches a requested behavior.
        Never invent APIs that are not implied by the code. Preserve naming, formatting, libraries, and architecture.
        Do not dump jargon. Prefer behavior and intent: who does what, when, and what happens if it fails.
        """
    }

    public static func explain(snippet: CodeSnippet, depth: ExplanationDepth) -> GenerationRequest {
        let system = """
        \(systemPersona)
        \(depth.promptGuidance)
        Translate this exact snippet into everyday English.
        Read every line of the snippet — and the rest of the file if provided — before writing any meaning.
        First write an overview of the whole snippet. Then write a meaning for every non-empty line.
        The line meanings are one story, not isolated captions:
        - Each meaning must be true of that line's actual code: real names, values, conditions, and calls.
        - Each meaning should still make sense after reading the lines above and below it.
        - When two lines talk about the same thing, use the same everyday name for it.
        - A later line should say what it does with what the earlier lines set up, not reintroduce it as if new.
        - Do not start a meaning with "After", and do not repeat the previous line's sentence.
        - Do not write generic glosses such as "this sets a variable", "this is a function", or "this is punctuation".
        - If a line is { or }, say which named block it opens or closes.
        Return ONLY valid JSON:
        {
          "overview": "short plain-English overview of the whole snippet",
          "lines": [
            { "line": 1, "meaning": "what this exact line does, in everyday language, given the rest of the snippet" }
          ]
        }
        Include one entry for every non-empty numbered line. Do not skip lines. Blank lines can be omitted.
        """

        let prompt = """
        \(codeContext(snippet, limit: 220))
        Write the overview and every line meaning so they fit this snippet together.
        """

        return GenerationRequest(prompt: prompt, system: system, jsonMode: true)
    }

    public static func cohere(snippet: CodeSnippet, draft: Explanation, depth: ExplanationDepth) -> GenerationRequest {
        let system = """
        \(systemPersona)
        \(depth.promptGuidance)
        You are revising a translation of code into English.
        You can see the code and every line's current English at once.
        Make the set consistent:
        - Fix a meaning that ignores the names, values, or action on that line.
        - Fix a meaning that contradicts, repeats, or fails to follow from the lines around it.
        - Keep a meaning that already fits the code and the neighboring English.
        - Use the same everyday name for the same thing across lines.
        - The overview must match the full set of line meanings.
        Return ONLY valid JSON with the same shape:
        {
          "overview": "short plain-English overview of the whole snippet",
          "lines": [
            { "line": 1, "meaning": "revised everyday meaning for this line" }
          ]
        }
        Return a meaning for every non-empty line, including ones you kept unchanged.
        """

        let prompt = """
        \(codeContext(snippet, limit: 220))
        Current translation of every line. Revise with the whole set in mind:
        \(translationSet(snippet: snippet, explanation: draft))
        """

        return GenerationRequest(prompt: prompt, system: system, jsonMode: true)
    }

    public static func change(request: EditRequest) -> GenerationRequest {
        let lineSpec = lineIntentBlock(request.lineIntents)
        let system = """
        \(systemPersona)
        Translate the user's English back into code for this snippet.
        Read every line's English together as one description of the snippet, then write code that matches that whole description.
        Use the original snippet as ground truth for language, names, types, libraries, and formatting.
        Do not invent APIs. Keep lines whose English is unchanged — that English is a contract.
        Change only what the new English requires, and keep those changes compatible with the English of the lines around them.
        If English asks for new behavior, write the smallest code that does that, matching nearby style.
        Return ONLY valid JSON:
        {
          "proposedSource": "full updated source for the provided snippet",
          "whatChangedEnglish": "one or two sentences in plain English describing the new behavior"
        }
        The proposedSource must be complete source for the same snippet, not a diff.
        """

        let prompt = """
        \(codeContext(request.snippet, limit: 300))
        Overall request: \(request.instruction.isEmpty ? "(none — follow the per-line English as a set)" : request.instruction)
        \(lineSpec)
        """

        return GenerationRequest(prompt: prompt, system: system, jsonMode: true)
    }

    public static func refineLanguage(code: String, heuristic: DetectedLanguage) -> GenerationRequest {
        let preview = code.split(separator: "\n").prefix(80).joined(separator: "\n")
        let system = """
        Identify the programming or markup language. Return ONLY JSON:
        { "name": "TypeScript", "identifier": "typescript", "confidence": "high|medium|low", "alternatives": ["JavaScript"] }
        If unsure, use low confidence. Do not guess wildly.
        """
        let prompt = """
        Heuristic guess: \(heuristic.name) (\(heuristic.confidence.rawValue))
        Code:
        \(preview)
        """
        return GenerationRequest(prompt: prompt, system: system, jsonMode: true)
    }

    public static func numberedSource(_ source: String, limit: Int = 80) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let limited = lines.prefix(limit)
        var numbered = limited.enumerated().map { index, line in
            "\(index + 1)| \(line)"
        }.joined(separator: "\n")
        if lines.count > limit {
            numbered += "\n… \(lines.count - limit) more lines omitted"
        }
        return numbered
    }

    public static func translationSet(snippet: CodeSnippet, explanation: Explanation) -> String {
        snippet.lines.enumerated().compactMap { index, line in
            let number = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let english = explanation.meaning(forLine: number) ?? "(missing)"
            return """
            L\(number)
              code: \(line)
              en: \(english)
            """
        }.joined(separator: "\n")
    }

    private static func codeContext(_ snippet: CodeSnippet, limit: Int) -> String {
        var surrounding = ""
        if let extra = snippet.surrounding,
           extra != snippet.source,
           extra.count > snippet.source.count {
            surrounding = "\nThe rest of the file, for context only — names, types, and neighbors live here:\n\(extra)\n"
        }
        return """
        File: \(snippet.fileName ?? "untitled")
        Language: \(snippet.language.name)
        \(surrounding)
        Snippet:
        \(numberedSource(snippet.source, limit: limit))
        """
    }

    private static func lineIntentBlock(_ intents: [LineIntent]) -> String {
        guard !intents.isEmpty else { return "" }
        let rows = intents.sorted { $0.line < $1.line }.map { intent in
            let mark = intent.didChange ? "CHANGED" : "same"
            return """
            L\(intent.line) [\(mark)]
              code: \(intent.source)
              was: \(intent.originalEnglish)
              should: \(intent.english)
            """
        }
        return "Desired behavior in English, by line. Read this as one description of the snippet:\n" + rows.joined(separator: "\n")
    }
}
