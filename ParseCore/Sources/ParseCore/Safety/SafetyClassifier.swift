import Foundation

public enum SafetyClassifier {
    public static func classify(original: String, proposed: String, instruction: String = "") -> [SafetyFlag] {
        let haystack = [original, proposed, instruction].joined(separator: "\n").lowercased()
        var flags: [SafetyFlag] = []
        var seen: Set<String> = []

        for rule in rules where rule.matches(haystack) {
            if seen.insert(rule.category).inserted {
                flags.append(
                    SafetyFlag(
                        title: rule.title,
                        consequence: rule.consequence,
                        severity: rule.severity,
                        category: rule.category
                    )
                )
            }
        }

        return flags.sorted { lhs, rhs in
            severityRank(lhs.severity) > severityRank(rhs.severity)
        }
    }

    private static func severityRank(_ severity: SafetySeverity) -> Int {
        switch severity {
        case .critical: 2
        case .warning: 1
        case .info: 0
        }
    }

    private struct Rule {
        var category: String
        var title: String
        var consequence: String
        var severity: SafetySeverity
        var patterns: [String]

        func matches(_ haystack: String) -> Bool {
            patterns.contains { haystack.contains($0) }
        }
    }

    private static let rules: [Rule] = [
        Rule(
            category: "authentication",
            title: "Authentication",
            consequence: "This change touches sign-in or identity checks. A mistake could lock people out or let the wrong person in.",
            severity: .critical,
            patterns: ["authentication", "signin", "sign-in", "sign_in", "oauth", "jwt", "password", "passcode", "biometric"]
        ),
        Rule(
            category: "permissions",
            title: "Permissions",
            consequence: "Access rules may change. Someone could gain or lose the ability to see or edit data.",
            severity: .warning,
            patterns: ["permission", "authorize", "authorization", "acl", "role-based", "rbac", "isadmin"]
        ),
        Rule(
            category: "credentials",
            title: "Credentials",
            consequence: "Secrets or login material appear in this change. They could leak if this code is shared or committed.",
            severity: .critical,
            patterns: ["api_key", "apikey", "secret_key", "client_secret", "private_key", "credential", "bearer ", "authorization:"]
        ),
        Rule(
            category: "database-deletion",
            title: "Database deletion",
            consequence: "This may delete stored records. Deleted data can be difficult or impossible to restore.",
            severity: .critical,
            patterns: ["drop table", "drop database", "truncate ", "delete from", "destroy_all", ".delete()", "force delete"]
        ),
        Rule(
            category: "file-deletion",
            title: "File deletion",
            consequence: "Files may be removed from disk. That can erase work that is not in version control.",
            severity: .critical,
            patterns: ["rm -rf", "rm -r", "unlink(", "filemanager.remove", "deletefile", "os.remove", "shutil.rmtree"]
        ),
        Rule(
            category: "payments",
            title: "Payments",
            consequence: "This touches charging or billing. A mistake could charge someone twice or skip a charge.",
            severity: .critical,
            patterns: ["stripe", "braintree", "paymentintent", "chargecustomer", "in-app purchase", "storekit", "billing"]
        ),
        Rule(
            category: "security",
            title: "Security settings",
            consequence: "Security configuration may change, which can weaken protection around this software.",
            severity: .warning,
            patterns: ["cors", "csrf", "content-security-policy", "allowallorigins", "disablehttps", "insecure", "sslverifypeer"]
        ),
        Rule(
            category: "environment",
            title: "Environment variables",
            consequence: "Environment or configuration values may change, which can point the app at the wrong service or leak settings.",
            severity: .warning,
            patterns: ["process.env", "getenv(", "environmentvariable", ".env", "userdefaults", "bundle.main.object(forinfo"]
        ),
        Rule(
            category: "destructive-commands",
            title: "Destructive commands",
            consequence: "This includes commands that can destroy data or take down a machine if they run.",
            severity: .critical,
            patterns: ["mkfs", "format c:", "shutdown", "sudo rm", ":(){", "dd if=", "kill -9"]
        )
    ]
}
