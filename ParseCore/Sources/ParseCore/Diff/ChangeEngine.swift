import Foundation

public enum ChangeEngine {
    public static func diff(original: String, proposed: String) -> [DiffLine] {
        let oldLines = splitLines(original)
        let newLines = splitLines(proposed)
        let operations = lcsOperations(oldLines, newLines)

        var hunks: [DiffLine] = []
        var oldIndex = 0
        var newIndex = 0

        for operation in operations {
            switch operation {
            case .equal(let count):
                for _ in 0..<count {
                    hunks.append(
                        DiffLine(
                            kind: .equal,
                            text: oldLines[oldIndex],
                            oldLine: oldIndex + 1,
                            newLine: newIndex + 1
                        )
                    )
                    oldIndex += 1
                    newIndex += 1
                }
            case .delete(let count):
                for _ in 0..<count {
                    hunks.append(
                        DiffLine(
                            kind: .delete,
                            text: oldLines[oldIndex],
                            oldLine: oldIndex + 1
                        )
                    )
                    oldIndex += 1
                }
            case .insert(let count):
                for _ in 0..<count {
                    hunks.append(
                        DiffLine(
                            kind: .insert,
                            text: newLines[newIndex],
                            newLine: newIndex + 1
                        )
                    )
                    newIndex += 1
                }
            }
        }

        return hunks
    }

    public static func proposedChange(
        original: String,
        proposed: String,
        whatChangedEnglish: String,
        safetyFlags: [SafetyFlag] = [],
        usedCloud: Bool = false,
        providerName: String = ""
    ) -> ProposedChange {
        ProposedChange(
            originalSource: original,
            proposedSource: proposed,
            whatChangedEnglish: whatChangedEnglish,
            hunks: diff(original: original, proposed: proposed),
            safetyFlags: safetyFlags,
            usedCloud: usedCloud,
            providerName: providerName
        )
    }

    private enum Operation {
        case equal(Int)
        case insert(Int)
        case delete(Int)
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func lcsOperations(_ old: [String], _ new: [String]) -> [Operation] {
        let m = old.count
        let n = new.count
        if m == 0 && n == 0 { return [] }
        if m == 0 { return [.insert(n)] }
        if n == 0 { return [.delete(m)] }

        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }

        var operationsReversed: [Operation] = []
        var i = m
        var j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                append(&operationsReversed, .equal(1))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                append(&operationsReversed, .insert(1))
                j -= 1
            } else {
                append(&operationsReversed, .delete(1))
                i -= 1
            }
        }

        return operationsReversed.reversed()
    }

    private static func append(_ operations: inout [Operation], _ next: Operation) {
        guard let last = operations.last else {
            operations.append(next)
            return
        }
        switch (last, next) {
        case (.equal(let a), .equal(let b)):
            operations[operations.count - 1] = .equal(a + b)
        case (.insert(let a), .insert(let b)):
            operations[operations.count - 1] = .insert(a + b)
        case (.delete(let a), .delete(let b)):
            operations[operations.count - 1] = .delete(a + b)
        default:
            operations.append(next)
        }
    }
}
