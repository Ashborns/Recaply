import Foundation

final class DeepseekClient: LLMProviding {
    static let shared = DeepseekClient()

    let providerName = "deepseek"
    private let endpointString = "https://api.deepseek.com/v1/chat/completions"
    private let model = "deepseek-chat"
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func complete(messages: [LLMMessage], jsonMode: Bool) async throws -> String {
        guard let apiKey = keychain.read("deepseek_key"), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(providerName)
        }
        guard let endpoint = URL(string: endpointString) else { throw LLMError.invalidEndpoint }
        return try await LLMClient.post(endpoint: endpoint, model: model, messages: messages,
                                        jsonMode: jsonMode, apiKey: apiKey, session: session)
    }
}
