import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var glmKey: String = ""
    @Published var deepseekKey: String = ""
    @Published var statusMessage: String?
    @Published var selectedModel: String = "GLM primary + Deepseek fallback"

    private let keychain: KeychainStore

    init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
        glmKey = keychain.read("glm_key") ?? ""
        deepseekKey = keychain.read("deepseek_key") ?? ""
    }

    var hasAnyKey: Bool {
        !glmKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !deepseekKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        saveOrDelete(glmKey, key: "glm_key")
        saveOrDelete(deepseekKey, key: "deepseek_key")
        statusMessage = hasAnyKey ? "Keys saved securely in Keychain." : "Add at least one API key to enable cloud summaries."
    }

    private func saveOrDelete(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychain.delete(key)
        } else {
            _ = keychain.save(trimmed, for: key)
        }
    }
}
