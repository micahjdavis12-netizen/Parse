import Foundation

public enum LanguageConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public struct DetectedLanguage: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var identifier: String
    public var confidence: LanguageConfidence
    public var alternatives: [String]
    public var wasDetectedAutomatically: Bool

    public init(
        name: String,
        identifier: String,
        confidence: LanguageConfidence,
        alternatives: [String] = [],
        wasDetectedAutomatically: Bool = true
    ) {
        self.name = name
        self.identifier = identifier
        self.confidence = confidence
        self.alternatives = alternatives
        self.wasDetectedAutomatically = wasDetectedAutomatically
    }

    public var headerText: String {
        switch confidence {
        case .high, .medium:
            return name
        case .low:
            return "\(name) · Uncertain"
        }
    }

    public static let unknown = DetectedLanguage(
        name: "Unknown",
        identifier: "unknown",
        confidence: .low,
        wasDetectedAutomatically: true
    )
}
