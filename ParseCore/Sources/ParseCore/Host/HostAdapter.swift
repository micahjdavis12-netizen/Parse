import Foundation

public struct HostSelection: Sendable, Equatable {
    public var source: String
    public var fileName: String?
    public var languageHint: String?
    public var canApplyDirectly: Bool

    public init(
        source: String,
        fileName: String? = nil,
        languageHint: String? = nil,
        canApplyDirectly: Bool = false
    ) {
        self.source = source
        self.fileName = fileName
        self.languageHint = languageHint
        self.canApplyDirectly = canApplyDirectly
    }
}

public struct CodeContext: Sendable, Equatable {
    public var surrounding: String?
    public var neighbors: [String]

    public init(surrounding: String? = nil, neighbors: [String] = []) {
        self.surrounding = surrounding
        self.neighbors = neighbors
    }

    public static let empty = CodeContext()
}

public enum ApplyResult: Sendable, Equatable {
    case inserted
    case copiedFallback(reason: String)
    case cancelled
    case failed(String)

    public var didInsert: Bool {
        if case .inserted = self { return true }
        return false
    }
}

public protocol HostAdapter: Sendable {
    func currentSelection() async -> HostSelection?
    func surroundingContext(for selection: HostSelection) async -> CodeContext
    func apply(change: ProposedChange, to selection: HostSelection) async -> ApplyResult
    func copy(_ text: String) async
}
