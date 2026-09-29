import Foundation

public enum SafetySeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct SafetyFlag: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var consequence: String
    public var severity: SafetySeverity
    public var category: String

    public init(
        id: UUID = UUID(),
        title: String,
        consequence: String,
        severity: SafetySeverity,
        category: String
    ) {
        self.id = id
        self.title = title
        self.consequence = consequence
        self.severity = severity
        self.category = category
    }
}
