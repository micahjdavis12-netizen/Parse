import Foundation

public enum SectionTitle {
    public static let allowed: [String] = [
        "Initialization",
        "Data",
        "User Interface",
        "Event Handling",
        "API Calls",
        "Validation",
        "Error Handling",
        "Database Operations",
        "Helper Functions",
        "Other"
    ]

    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Overview" }

        if trimmed.contains("|") {
            let parts = trimmed
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 3 {
                return "Overview"
            }
            if let match = allowed.first(where: { parts.contains($0) }) {
                return match
            }
            return parts.first ?? "Overview"
        }

        if let exact = allowed.first(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }
        return trimmed
    }
}
