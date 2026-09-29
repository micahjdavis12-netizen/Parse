import Foundation

public enum ExplanationDepth: String, Codable, Sendable, CaseIterable, Identifiable {
    case simple
    case detailed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simple: "Simple"
        case .detailed: "Detailed"
        }
    }

    public var promptGuidance: String {
        switch self {
        case .simple:
            """
            Explain as if the reader has little programming experience.
            Prefer everyday language. Avoid jargon unless a short plain-English gloss is included.
            Focus on what happens for a person using the software.
            """
        case .detailed:
            """
            Explain architecture, data flow, dependencies, edge cases, and implementation details.
            Still map explanations to what the code actually does, not a generic summary.
            """
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "detailed", "developer":
            self = .detailed
        default:
            self = .simple
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
