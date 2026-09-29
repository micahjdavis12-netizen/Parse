import SwiftUI
import ParseCore

struct SettingsView: View {
    @Bindable var session: SessionStore
    @Bindable var cloud: CloudSettings
    @State private var showAdvanced = false

    init(session: SessionStore) {
        self.session = session
        self.cloud = session.cloudSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(ParseTheme.headerFont)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    translationSection
                    apiSection
                    macSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background)
        .frame(minWidth: 440, minHeight: 460)
    }

    private var translationSection: some View {
        settingsSection("Translation") {
            Picker("Depth", selection: Binding(
                get: { session.depth },
                set: { session.changeDepth($0) }
            )) {
                ForEach(ExplanationDepth.allCases) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 220, alignment: .leading)
            Text("Simple stays in everyday language. Detailed includes how the code is put together.")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var apiSection: some View {
        settingsSection("API key") {
            Text("Used when a translation is too large for this Mac. Everyday explanations stay on device.")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Provider", selection: $cloud.kind) {
                ForEach(CloudProviderConfiguration.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            settingsField("API key") {
                SecureField(cloud.hasSavedKey ? "Key saved" : "sk-…", text: $cloud.apiKeyDraft)
            }

            HStack(spacing: 8) {
                Button("Save") {
                    cloud.saveKey()
                    session.retryTranslationWithAPIKey()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Clear") { cloud.clearKey() }
                    .controlSize(.small)
                Spacer()
                Button("Test") {
                    Task { await cloud.testConnection() }
                }
                .controlSize(.small)
                .disabled(!cloud.hasSavedKey && cloud.apiKeyDraft.isEmpty)
            }

            if cloud.hasSavedKey {
                Label("A key is saved in the Keychain.", systemImage: "checkmark.circle")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            if let message = cloud.testMessage {
                Text(message)
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsField("Model") {
                        TextField("Default for provider", text: $cloud.model)
                    }
                    settingsField("Base URL") {
                        TextField("https://api.openai.com/v1", text: $cloud.baseURL)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced")
                    .font(ParseTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macSection: some View {
        settingsSection("On this Mac") {
            statusRow("Apple Intelligence") {
                Text(session.canUseOnDevice ? "Available" : "Unavailable")
                    .foregroundStyle(session.canUseOnDevice ? Color.secondary : Color.orange)
            }
            statusRow("Read code editors") {
                Button(AccessibilityBridge.isTrusted(prompt: false) ? "Allowed" : "Allow") {
                    if !AccessibilityBridge.isTrusted(prompt: true) {
                        AccessibilityBridge.openSystemSettings()
                    }
                }
                .controlSize(.small)
            }
            statusRow("Shortcut") {
                HotkeyLabel()
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
            content()
            Divider()
                .padding(.top, 6)
        }
    }

    private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ParseTheme.captionFont)
                .foregroundStyle(.tertiary)
            content()
                .textFieldStyle(.plain)
                .font(ParseTheme.explanationFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: ParseTheme.controlRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ParseTheme.controlRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func statusRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(ParseTheme.explanationFont)
            Spacer(minLength: 8)
            trailing()
                .font(ParseTheme.captionFont)
        }
    }
}
