import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    struct AIProviderDiagnostic: Identifiable {
        let id: String
        let name: String
        let role: String
        let isConfigured: Bool
        let modelName: String
        let maskedKey: String
        let source: String
        let securityNote: String

        var isProductionSafe: Bool {
            source == "Keychain"
        }
    }

    private let keychain: KeychainStore

    init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    var isGLMConfigured: Bool {
        LocalEnvironment.value(for: "GLM_API_KEY").map { !$0.isEmpty } ?? false ||
        keychain.read("glm_key").map { !$0.isEmpty } ?? false
    }

    var isGroqConfigured: Bool {
        LocalEnvironment.value(for: "GROQ_API_KEY").map { !$0.isEmpty } ?? false ||
        keychain.read("groq_key").map { !$0.isEmpty } ?? false
    }

    var hasAnyAIProviderConfigured: Bool {
        isGLMConfigured || isGroqConfigured
    }

    var glmModelName: String {
        LocalEnvironment.value(for: "GLM_MODEL") ?? "glm-4.7"
    }

    var groqModelName: String {
        LocalEnvironment.value(for: "GROQ_MODEL") ?? "llama-3.1-8b-instant"
    }

    var aiEngineDescription: String {
        switch (isGLMConfigured, isGroqConfigured) {
        case (true, true):
            return "Primary Groq · \(groqModelName) · fallback GLM / Z.ai · \(glmModelName)"
        case (true, false):
            return "Groq missing; GLM / Z.ai fallback available · \(glmModelName)"
        case (false, true):
            return "Primary Groq ready · \(groqModelName)"
        case (false, false):
            return "Offline fallback is active."
        }
    }

    var aiProviderDiagnostics: [AIProviderDiagnostic] {
        [
            diagnostic(
                id: "glm",
                name: "GLM / Z.ai",
                role: "Fallback AI",
                keychainKey: "glm_key",
                environmentKey: "GLM_API_KEY",
                modelName: glmModelName
            ),
            diagnostic(
                id: "groq",
                name: "Groq",
                role: "Primary AI",
                keychainKey: "groq_key",
                environmentKey: "GROQ_API_KEY",
                modelName: groqModelName
            )
        ]
    }

    var isClassifierAvailable: Bool {
        CoreMLClassifierProvider.shared.isAvailable
    }

    private func diagnostic(id: String, name: String, role: String, keychainKey: String, environmentKey: String, modelName: String) -> AIProviderDiagnostic {
        if let keychainValue = keychain.read(keychainKey), !keychainValue.isEmpty {
            return AIProviderDiagnostic(
                id: id,
                name: name,
                role: role,
                isConfigured: true,
                modelName: modelName,
                maskedKey: Self.maskedKey(keychainValue),
                source: "Keychain",
                securityNote: "Safer for production builds."
            )
        }

        if let envValue = LocalEnvironment.value(for: environmentKey), !envValue.isEmpty {
            return AIProviderDiagnostic(
                id: id,
                name: name,
                role: role,
                isConfigured: true,
                modelName: modelName,
                maskedKey: Self.maskedKey(envValue),
                source: "Local .env",
                securityNote: "Dev-only. Avoid bundling API keys in production."
            )
        }

        return AIProviderDiagnostic(
            id: id,
            name: name,
            role: role,
            isConfigured: false,
            modelName: modelName,
            maskedKey: "Not set",
            source: "Missing",
            securityNote: "Local fallback will be used when this provider is needed."
        )
    }

    private static func maskedKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return String(repeating: "•", count: max(trimmed.count, 4)) }

        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(3)
        return "\(prefix)…\(suffix)"
    }
}
