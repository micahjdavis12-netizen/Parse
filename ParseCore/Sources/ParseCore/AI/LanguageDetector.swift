import Foundation

public struct LanguageMatch: Equatable, Sendable {
    public var language: DetectedLanguage
    public var score: Int
}

public enum LanguageDetector {
    public static func detect(code: String, fileName: String? = nil, hint: String? = nil) -> DetectedLanguage {
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown
        }

        var scores: [String: Int] = [:]

        if let fileName {
            if let fromFile = language(fromFileName: fileName) {
                scores[fromFile.identifier, default: 0] += 8
            }
        }

        if let hint, let fromHint = Self.language(named: hint) {
            scores[fromHint.identifier, default: 0] += 6
        }

        let shebang = code.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if shebang.hasPrefix("#!") {
            if shebang.contains("python") { scores["python", default: 0] += 10 }
            else if shebang.contains("node") { scores["javascript", default: 0] += 10 }
            else if shebang.contains("bash") || shebang.contains("/sh") { scores["shell", default: 0] += 10 }
            else if shebang.contains("zsh") { scores["shell", default: 0] += 10 }
            else if shebang.contains("pwsh") || shebang.contains("powershell") { scores["powershell", default: 0] += 10 }
            else if shebang.contains("ruby") { scores["ruby", default: 0] += 10 }
            else if shebang.contains("php") { scores["php", default: 0] += 10 }
            else if shebang.contains("osascript") { scores["applescript", default: 0] += 10 }
        }

        for signature in signatures {
            if signature.patterns.contains(where: { code.range(of: $0, options: .regularExpression) != nil }) {
                scores[signature.identifier, default: 0] += signature.weight
            }
        }

        let ranked = scores
            .map { identifier, score in
                LanguageMatch(language: catalog[identifier] ?? .unknown, score: score)
            }
            .sorted { $0.score > $1.score }

        guard let best = ranked.first, best.score > 0 else {
            return DetectedLanguage(
                name: "Plain text",
                identifier: "text",
                confidence: .low,
                alternatives: []
            )
        }

        let confidence: LanguageConfidence
        if best.score >= 8 {
            confidence = .high
        } else if best.score >= 4 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let alternatives = ranked.dropFirst().prefix(3).map(\.language.name)

        var language = best.language
        language.confidence = confidence
        language.alternatives = Array(alternatives)
        language.wasDetectedAutomatically = true
        return language
    }

    public static func language(named raw: String) -> DetectedLanguage? {
        let key = normalize(raw)
        if let match = catalog[key] { return match }
        return catalog.values.first { normalize($0.name) == key || $0.identifier == key }
    }

    private static func language(fromFileName fileName: String) -> DetectedLanguage? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "js": return catalog["javascript"]
        case "mjs", "cjs": return catalog["javascript"]
        case "jsx": return catalog["jsx"]
        case "ts": return catalog["typescript"]
        case "tsx": return catalog["tsx"]
        case "py": return catalog["python"]
        case "java": return catalog["java"]
        case "c", "h": return catalog["c"]
        case "cc", "cpp", "cxx", "hpp": return catalog["cpp"]
        case "cs": return catalog["csharp"]
        case "go": return catalog["go"]
        case "rs": return catalog["rust"]
        case "swift": return catalog["swift"]
        case "kt", "kts": return catalog["kotlin"]
        case "php": return catalog["php"]
        case "rb": return catalog["ruby"]
        case "html", "htm": return catalog["html"]
        case "css": return catalog["css"]
        case "scss", "sass": return catalog["css"]
        case "sql": return catalog["sql"]
        case "json": return catalog["json"]
        case "yml", "yaml": return catalog["yaml"]
        case "sh", "bash", "zsh": return catalog["shell"]
        case "ps1": return catalog["powershell"]
        case "lua": return catalog["lua"]
        case "dart": return catalog["dart"]
        case "vue": return catalog["vue"]
        default: return nil
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "#", with: "sharp")
            .replacingOccurrences(of: "++", with: "pp")
    }

    private struct Signature {
        var identifier: String
        var weight: Int
        var patterns: [String]
    }

    private static let signatures: [Signature] = [
        Signature(identifier: "json", weight: 6, patterns: [#"^\s*[\[\{]"#, #""[^"]+"\s*:"#]),
        Signature(identifier: "yaml", weight: 4, patterns: [#"^[A-Za-z0-9_\-]+:\s"#, #"^---\s*$"#]),
        Signature(identifier: "html", weight: 6, patterns: [#"<(html|div|span|body|head|!DOCTYPE)\b"#]),
        Signature(identifier: "css", weight: 5, patterns: [#"^[^{]+\{[^}]*:[^}]+\}"#]),
        Signature(identifier: "sql", weight: 6, patterns: [#"\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|CREATE TABLE)\b"#]),
        Signature(identifier: "tsx", weight: 8, patterns: [#"\b(import|export).+from\s+['\"]"#, #":\s*(string|number|boolean|React\.)"#, #"<[A-Z][A-Za-z0-9]*[\s>]"#]),
        Signature(identifier: "jsx", weight: 7, patterns: [#"\b(import|export).+from\s+['\"]"#, #"\bfunction\b.+\{\s*return\s*\("#, #"<[A-Z][A-Za-z0-9]*[\s>]"#]),
        Signature(identifier: "typescript", weight: 7, patterns: [#"\b(interface|type)\s+[A-Z]"#, #":\s*(string|number|boolean|void)\b"#, #"import\s+type\b"#]),
        Signature(identifier: "javascript", weight: 5, patterns: [#"\b(const|let|var|function|=>)\b"#, #"console\.log\("#]),
        Signature(identifier: "python", weight: 6, patterns: [#"^\s*def\s+\w+\("#, #"^\s*(async\s+)?def\s+"#, #"^\s*from\s+\w+\s+import\b"#, #"^\s*if\s+__name__\s*=="#]),
        Signature(identifier: "swift", weight: 7, patterns: [#"\b(func|var|let|guard|struct|enum|actor)\b"#, #"\b(import SwiftUI|import Foundation|@MainActor)\b"#]),
        Signature(identifier: "rust", weight: 7, patterns: [#"\bfn\s+\w+"#, #"\b(let mut|impl |pub struct|match )\b"#]),
        Signature(identifier: "go", weight: 6, patterns: [#"\bpackage\s+\w+"#, #"\bfunc\s+\("#, #"\bfmt\."#]),
        Signature(identifier: "java", weight: 6, patterns: [#"\b(public|private)\s+(class|interface|static)"#, #"System\.out\.println"#]),
        Signature(identifier: "kotlin", weight: 6, patterns: [#"\bfun\s+\w+"#, #"\b(val|var)\s+\w+"#, #"companion object"#]),
        Signature(identifier: "csharp", weight: 6, patterns: [#"\busing\s+System"#, #"\bnamespace\s+"#, #"\b(public|private)\s+(class|void|async)"#]),
        Signature(identifier: "cpp", weight: 5, patterns: [#"#include\s*<"#, #"\bstd::"#, #"\bint\s+main\s*\("#]),
        Signature(identifier: "c", weight: 4, patterns: [#"#include\s*<stdio.h>"#, #"\bprintf\("#]),
        Signature(identifier: "php", weight: 6, patterns: [#"<\?php"#, #"\$\w+\s*="#]),
        Signature(identifier: "ruby", weight: 5, patterns: [#"\bdef\s+\w+"#, #"\bend\b"#, #"puts\s+"#]),
        Signature(identifier: "shell", weight: 5, patterns: [#"^\s*(echo|export|if\s+\[)"#, #"\$\{?\w+\}?"#]),
        Signature(identifier: "powershell", weight: 6, patterns: [#"\$\w+\s*=", #"Write-Host"#, #"Get-\w+"#]),
        Signature(identifier: "lua", weight: 5, patterns: [#"\blocal\s+\w+"#, #"\bfunction\s+\w+"#, #"end\s*$"#]),
        Signature(identifier: "dart", weight: 6, patterns: [#"\bvoid\s+main\s*\("#, #"Widget\s+build\(", #"import\s+'package:flutter"#]),
        Signature(identifier: "vue", weight: 7, patterns: [#"<template>"#, #"<script setup>"#])
    ]

    private static let catalog: [String: DetectedLanguage] = {
        let items: [(String, String)] = [
            ("javascript", "JavaScript"),
            ("typescript", "TypeScript"),
            ("jsx", "React/JSX"),
            ("tsx", "React/TSX"),
            ("python", "Python"),
            ("java", "Java"),
            ("c", "C"),
            ("cpp", "C++"),
            ("csharp", "C#"),
            ("go", "Go"),
            ("rust", "Rust"),
            ("swift", "Swift"),
            ("kotlin", "Kotlin"),
            ("php", "PHP"),
            ("ruby", "Ruby"),
            ("html", "HTML"),
            ("css", "CSS"),
            ("sql", "SQL"),
            ("json", "JSON"),
            ("yaml", "YAML"),
            ("shell", "Shell/Bash"),
            ("powershell", "PowerShell"),
            ("lua", "Lua"),
            ("dart", "Dart"),
            ("vue", "Vue"),
            ("applescript", "AppleScript"),
            ("text", "Plain text")
        ]
        return Dictionary(uniqueKeysWithValues: items.map { identifier, name in
            (identifier, DetectedLanguage(name: name, identifier: identifier, confidence: .medium))
        })
    }()
}
