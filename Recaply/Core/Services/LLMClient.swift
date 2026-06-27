import Foundation

struct LLMMessage: Codable, Equatable {
    let role: String
    let content: String
}

protocol LLMProviding {
    var providerName: String { get }
    func complete(messages: [LLMMessage], jsonMode: Bool) async throws -> String
}

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case invalidEndpoint
    case transport(String)
    case invalidResponse
    case emptyChoice

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider)."
        case .invalidEndpoint:
            return "The LLM endpoint URL is invalid."
        case .transport(let message):
            return "LLM request failed: \(message)"
        case .invalidResponse:
            return "The LLM returned an invalid response."
        case .emptyChoice:
            return "The LLM response did not include a message."
        }
    }
}

final class LLMClient: LLMProviding {
    static let shared = LLMClient()

    let providerName = "glm"
    private let endpointString = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    private let model = "glm-4-flash"
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func complete(messages: [LLMMessage], jsonMode: Bool) async throws -> String {
        guard let apiKey = keychain.read("glm_key"), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(providerName)
        }
        guard let endpoint = URL(string: endpointString) else { throw LLMError.invalidEndpoint }
        return try await Self.post(endpoint: endpoint, model: model, messages: messages,
                                   jsonMode: jsonMode, apiKey: apiKey, session: session)
    }

    static func post(endpoint: URL, model: String, messages: [LLMMessage], jsonMode: Bool,
                     apiKey: String, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatRequest(model: model, messages: messages,
                               responseFormat: jsonMode ? ResponseFormat(type: "json_object") : nil)
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP error"
                throw LLMError.transport(message)
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyChoice
            }
            return content
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
    }
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }
}

private struct ResponseFormat: Codable {
    let type: String
}

private struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

enum PromptBuilder {
    static func enhancement(segments: [TranscriptSegmentModel], tag: SessionTag) -> [LLMMessage] {
        let transcript = segments.map { segment in
            "[\(segment.index) @\(Int(segment.timestamp))s] [\(segment.label.rawValue)] \(segment.text)"
        }.joined(separator: "\n")
        let system = "You clean up a \(tag.rawValue) transcript. Return JSON ONLY: " +
            "{\"clean\":[{\"index\":0,\"text\":\"...\"}],\"polished\":[{\"heading\":\"...\",\"body\":\"...\"}]}. " +
            "clean fixes punctuation and removes filler while preserving each segment index and order. " +
            "polished restructures the whole talk into topic sections."
        return [LLMMessage(role: "system", content: system), LLMMessage(role: "user", content: transcript)]
    }

    static func summary(segments: [TranscriptSegmentModel], tag: SessionTag) -> [LLMMessage] {
        let body = segments.map { "[\($0.label.rawValue)] \($0.text)" }.joined(separator: "\n")
        let system = "Summarize this \(tag.rawValue). Return JSON ONLY: " +
            "{\"overview\":\"...\",\"actionItems\":[\"...\"],\"decisions\":[\"...\"],\"keyPoints\":[\"...\"]}."
        return [LLMMessage(role: "system", content: system), LLMMessage(role: "user", content: body)]
    }
}
