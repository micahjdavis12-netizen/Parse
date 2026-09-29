import Foundation
import ParseCore
import Observation

@MainActor
@Observable
final class CloudSettings {
    var kind: CloudProviderConfiguration.Kind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: Keys.kind) }
    }

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    var apiKeyDraft: String = ""
    var hasSavedKey: Bool = false
    var testMessage: String?

    init() {
        let storedKind = UserDefaults.standard.string(forKey: Keys.kind) ?? CloudProviderConfiguration.Kind.openai.rawValue
        self.kind = CloudProviderConfiguration.Kind(rawValue: storedKind) ?? .openai
        self.baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? ""
        self.model = UserDefaults.standard.string(forKey: Keys.model) ?? ""
        let key = KeychainStore.load() ?? ""
        self.hasSavedKey = !key.isEmpty
        self.apiKeyDraft = ""
    }

    var configuration: CloudProviderConfiguration {
        CloudProviderConfiguration(
            kind: kind,
            apiKey: KeychainStore.load() ?? "",
            baseURL: baseURL,
            model: model
        )
    }

    func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainStore.delete()
            hasSavedKey = false
        } else {
            try? KeychainStore.save(trimmed)
            hasSavedKey = true
            apiKeyDraft = ""
        }
        testMessage = nil
    }

    func clearKey() {
        try? KeychainStore.delete()
        apiKeyDraft = ""
        hasSavedKey = false
        testMessage = nil
    }

    func testConnection() async {
        let provider = OpenAICompatibleProvider(configuration: configuration)
        guard provider.isAvailable else {
            testMessage = "Add an API key first."
            return
        }
        do {
            _ = try await provider.testConnection()
            testMessage = "Connection succeeded."
        } catch {
            testMessage = error.localizedDescription
        }
    }

    private enum Keys {
        static let kind = "parse.cloud.kind"
        static let baseURL = "parse.cloud.baseURL"
        static let model = "parse.cloud.model"
    }
}
