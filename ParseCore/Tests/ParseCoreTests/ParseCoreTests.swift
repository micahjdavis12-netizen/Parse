import Foundation
@testable import ParseCore
import Testing

struct LanguageDetectorTests {
    @Test func detectsPython() {
        let code = """
        def greet(name):
            print(f"Hello {name}")

        if __name__ == "__main__":
            greet("Ada")
        """
        let language = LanguageDetector.detect(code: code, fileName: "app.py")
        #expect(language.identifier == "python")
        #expect(language.confidence != .low)
    }

    @Test func detectsTypeScript() {
        let code = """
        export function add(a: number, b: number): number {
          return a + b
        }
        """
        let language = LanguageDetector.detect(code: code, fileName: "math.ts")
        #expect(language.identifier == "typescript")
    }

    @Test func uncertainForPlainProse() {
        let language = LanguageDetector.detect(code: "hello there, this is just a sentence.")
        #expect(language.confidence == .low)
    }
}

struct ChangeEngineTests {
    @Test func producesInsertAndDelete() {
        let original = "a\nb\nc"
        let proposed = "a\nx\nc"
        let hunks = ChangeEngine.diff(original: original, proposed: proposed)
        #expect(hunks.contains { $0.kind == .delete && $0.text == "b" })
        #expect(hunks.contains { $0.kind == .insert && $0.text == "x" })
        #expect(hunks.contains { $0.kind == .equal && $0.text == "a" })
    }

    @Test func emptyFiles() {
        #expect(ChangeEngine.diff(original: "", proposed: "").isEmpty)
        let added = ChangeEngine.diff(original: "", proposed: "hi")
        #expect(added.count == 1)
        #expect(added.first?.kind == .insert)
    }
}

struct SafetyClassifierTests {
    @Test func flagsDestructiveSQL() {
        let flags = SafetyClassifier.classify(
            original: "SELECT * FROM users",
            proposed: "DELETE FROM users",
            instruction: "wipe the table"
        )
        #expect(flags.contains { $0.category == "database-deletion" })
    }

    @Test func quietOnBenignChange() {
        let flags = SafetyClassifier.classify(
            original: "print('hi')",
            proposed: "print('hello')",
            instruction: "change the greeting"
        )
        #expect(flags.isEmpty)
    }
}

struct ModelRouterTests {
    @Test func smallEditStaysOnDevice() {
        let router = ModelRouter(cloudAvailable: true, onDeviceAvailable: true)
        let snippet = CodeSnippet(source: "print('hi')\nprint('there')", language: LanguageDetector.detect(code: "print('hi')", fileName: "a.py"))
        let job = TranslationJob(kind: .edit, snippet: snippet, instruction: "say hello")
        let decision = router.decision(for: job)
        #expect(decision.route == .onDevice)
        #expect(decision.showCloudHint == false)
    }

    @Test func largeEditUsesCloudWhenKeyExists() {
        let router = ModelRouter(cloudAvailable: true, onDeviceAvailable: true)
        let source = (1...220).map { "line \($0)" }.joined(separator: "\n")
        let snippet = CodeSnippet(source: source)
        let job = TranslationJob(kind: .edit, snippet: snippet, instruction: "rename everything")
        let decision = router.decision(for: job)
        #expect(decision.route == .cloud)
        #expect(decision.isLargeChange)
    }

    @Test func largeEditWithoutKeyHintsSettings() {
        let router = ModelRouter(cloudAvailable: false, onDeviceAvailable: true)
        let source = (1...220).map { "line \($0)" }.joined(separator: "\n")
        let job = TranslationJob(kind: .edit, snippet: CodeSnippet(source: source), instruction: "rename")
        let decision = router.decision(for: job)
        #expect(decision.route == .onDevice)
        #expect(decision.showCloudHint)
    }
}

struct LineMeaningFillerTests {
    @Test func keepsProvidedMeaningsAndFillsTheRest() {
        let source = """
        func greet(name) {
          print(name)
        }
        """
        let explanation = Explanation(
            overview: "It greets someone by name.",
            sections: [
                ExplanationSection(title: "Greeting", plainEnglish: "It prints the name that was passed in.", startLine: 1, endLine: 3)
            ],
            lineMeanings: [
                LineExplanation(line: 2, meaning: "This prints the name on the screen.")
            ],
            language: .unknown,
            depth: .simple
        )
        let filled = LineMeaningFiller.fill(source: source, explanation: explanation)
        let meanings = Dictionary(uniqueKeysWithValues: filled.lineMeanings.map { ($0.line, $0.meaning) })
        #expect(meanings[2] == "This prints the name on the screen.")
        #expect(meanings[1]?.localizedCaseInsensitiveContains("prints the name") == true)
        #expect(meanings[3]?.localizedCaseInsensitiveContains("prints the name") == true)
        #expect(filled.lineMeanings.count == 3)
    }

    @Test func missingLineUsesNeighborTranslation() {
        let source = """
        let name = "Ada"
        print(name)
        """
        let explanation = Explanation(
            overview: "It remembers Ada and shows her name.",
            lineMeanings: [
                LineExplanation(line: 2, meaning: "Shows Ada's name on the screen.")
            ],
            language: .unknown,
            depth: .simple
        )
        let filled = LineMeaningFiller.fill(source: source, explanation: explanation)
        let first = filled.meaning(forLine: 1) ?? ""
        #expect(first.localizedCaseInsensitiveContains("Ada") || first.contains("name"))
        #expect(first.localizedCaseInsensitiveContains("Shows Ada") || first.localizedCaseInsensitiveContains("screen"))
    }

    @Test func mergeKeepsDraftWhenRefinedLineIsBlank() {
        let source = "a = 1\nb = 2"
        let draft = Explanation(
            overview: "Two values.",
            lineMeanings: [
                LineExplanation(line: 1, meaning: "Remembers 1 as a."),
                LineExplanation(line: 2, meaning: "Remembers 2 as b.")
            ],
            language: .unknown,
            depth: .simple
        )
        let refined = Explanation(
            overview: "It stores two numbers.",
            lineMeanings: [
                LineExplanation(line: 1, meaning: "Keeps 1 in a so the next line can use it.")
            ],
            language: .unknown,
            depth: .simple
        )
        let merged = LineMeaningFiller.merging(source: source, draft: draft, refined: refined)
        #expect(merged.overview == "It stores two numbers.")
        #expect(merged.meaning(forLine: 1) == "Keeps 1 in a so the next line can use it.")
        #expect(merged.meaning(forLine: 2) == "Remembers 2 as b.")
    }

    @Test func skipsBlankLines() {
        let source = "let a = 1\n\nlet b = 2"
        let explanation = Explanation(overview: "Two values.", language: .unknown, depth: .simple)
        let filled = LineMeaningFiller.fill(source: source, explanation: explanation)
        #expect(filled.lineMeanings.map(\.line) == [1, 3])
    }

    @Test func stringLiteralsDoNotStackAfter() {
        let source = """
        const flags = [
        'no-install',
        'quiet',
        ]
        """
        let explanation = Explanation(
            overview: "A list of flags.",
            lineMeanings: [
                LineExplanation(line: 1, meaning: "Starts the list of flags.")
            ],
            language: .unknown,
            depth: .simple
        )
        let filled = LineMeaningFiller.fill(source: source, explanation: explanation)
        let quiet = filled.meaning(forLine: 3) ?? ""
        #expect(quiet == "The value 'quiet'.")
        #expect(quiet.localizedCaseInsensitiveContains("after") == false)
    }
}

struct SectionTitleTests {
    @Test func dumpsOfAllowedTitlesBecomeOverview() {
        let dumped = "Initialization|Data|User Interface|Event Handling|API Calls|Validation|Error Handling|Database Operations|Helper Functions|Other"
        #expect(SectionTitle.normalize(dumped) == "Overview")
    }

    @Test func keepsARealTitle() {
        #expect(SectionTitle.normalize("Event Handling") == "Event Handling")
        #expect(SectionTitle.normalize("event handling") == "Event Handling")
    }
}

struct LineIntentPromptTests {
    @Test func changePromptIncludesPerLineEnglish() {
        let snippet = CodeSnippet(source: "print('hi')")
        let request = EditRequest(
            instruction: "",
            snippet: snippet,
            lineIntents: [
                LineIntent(
                    line: 1,
                    source: "print('hi')",
                    english: "Show hello instead",
                    originalEnglish: "Prints hi"
                )
            ]
        )
        let generation = TranslationPrompts.change(request: request)
        #expect(generation.prompt.contains("Show hello instead"))
        #expect(generation.prompt.contains("CHANGED"))
        #expect(generation.system.contains("one description of the snippet"))
    }

    @Test func unchangedLineIsMarkedSame() {
        let intent = LineIntent(
            line: 1,
            source: "print('hi')",
            english: "Prints hi",
            originalEnglish: "Prints hi"
        )
        #expect(intent.didChange == false)
        let request = EditRequest(instruction: "keep it", snippet: CodeSnippet(source: "print('hi')"), lineIntents: [intent])
        #expect(TranslationPrompts.change(request: request).prompt.contains("[same]"))
    }
}

struct ContextLimitTests {
    @Test func recognizesTheOnDeviceContextWarning() {
        #expect(ParseError.isContextLimitMessage("The session's transcript exceeded the model's context size."))
        #expect(ParseError.isContextLimitMessage("This file is fine.") == false)
    }
}

struct CoherePromptTests {
    @Test func coherePromptIncludesEveryTranslationAndTheCode() {
        let snippet = CodeSnippet(source: "let name = \"Ada\"\nprint(name)")
        let draft = Explanation(
            overview: "It shows Ada.",
            lineMeanings: [
                LineExplanation(line: 1, meaning: "Remembers Ada as name."),
                LineExplanation(line: 2, meaning: "Prints that name.")
            ],
            language: .unknown,
            depth: .simple
        )
        let request = TranslationPrompts.cohere(snippet: snippet, draft: draft, depth: .simple)
        #expect(request.prompt.contains("Remembers Ada as name."))
        #expect(request.prompt.contains("Prints that name."))
        #expect(request.prompt.contains("let name"))
        #expect(request.system.contains("every line's current English"))
    }

    @Test func explainPromptAsksForASingleStory() {
        let request = TranslationPrompts.explain(
            snippet: CodeSnippet(source: "print('hi')"),
            depth: .simple
        )
        #expect(request.system.contains("one story"))
        #expect(request.system.contains("lines above and below"))
    }
}
