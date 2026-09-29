import Foundation

public enum DiffKind: String, Codable, Sendable {
    case equal
    case insert
    case delete
}

public struct DiffLine: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var kind: DiffKind
    public var text: String
    public var oldLine: Int?
    public var newLine: Int?

    public init(
        id: UUID = UUID(),
        kind: DiffKind,
        text: String,
        oldLine: Int? = nil,
        newLine: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.oldLine = oldLine
        self.newLine = newLine
    }
}

public struct ProposedChange: Codable, Sendable, Equatable {
    public var originalSource: String
    public var proposedSource: String
    public var whatChangedEnglish: String
    public var hunks: [DiffLine]
    public var safetyFlags: [SafetyFlag]
    public var usedCloud: Bool
    public var providerName: String

    public init(
        originalSource: String,
        proposedSource: String,
        whatChangedEnglish: String,
        hunks: [DiffLine],
        safetyFlags: [SafetyFlag] = [],
        usedCloud: Bool = false,
        providerName: String = ""
    ) {
        self.originalSource = originalSource
        self.proposedSource = proposedSource
        self.whatChangedEnglish = whatChangedEnglish
        self.hunks = hunks
        self.safetyFlags = safetyFlags
        self.usedCloud = usedCloud
        self.providerName = providerName
    }

    public var hasSafetyFlags: Bool {
        !safetyFlags.isEmpty
    }

    public var isNoOp: Bool {
        originalSource == proposedSource
    }
}
