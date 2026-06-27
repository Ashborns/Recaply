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
    private let endpointString = "https://api.z.ai/api/coding/paas/v4/chat/completions"
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func complete(messages: [LLMMessage], jsonMode: Bool) async throws -> String {
        guard let apiKey = keychain.read("glm_key") ?? LocalEnvironment.value(for: "GLM_API_KEY"),
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(providerName)
        }
        guard let endpoint = URL(string: endpointString) else { throw LLMError.invalidEndpoint }
        let model = LocalEnvironment.value(for: "GLM_MODEL") ?? "glm-4.7"
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

final class GroqLLMClient: LLMProviding {
    static let shared = GroqLLMClient()

    let providerName = "groq"
    private let endpointString = "https://api.groq.com/openai/v1/chat/completions"
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func complete(messages: [LLMMessage], jsonMode: Bool) async throws -> String {
        guard let apiKey = keychain.read("groq_key") ?? LocalEnvironment.value(for: "GROQ_API_KEY"),
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(providerName)
        }
        guard let endpoint = URL(string: endpointString) else { throw LLMError.invalidEndpoint }
        let model = LocalEnvironment.value(for: "GROQ_MODEL") ?? "llama-3.1-8b-instant"
        return try await LLMClient.post(endpoint: endpoint, model: model, messages: messages,
                                        jsonMode: jsonMode, apiKey: apiKey, session: session)
    }
}

struct AIServiceResult<Payload> {
    let payload: Payload
    let warning: String?
}

enum AIServiceWarning {
    static func recoveredWithFallback(primary: LLMProviding, fallback: LLMProviding, error: Error) -> String {
        "AI server issue: \(primary.providerName) failed (\(friendly(error))). Recaply recovered with \(fallback.providerName) fallback, so the result may be slightly different."
    }

    private static func friendly(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }
}

enum AIProviderFailure: LocalizedError {
    case allProvidersFailed(primary: LLMProviding, fallback: LLMProviding?, errors: [Error])

    var errorDescription: String? {
        switch self {
        case .allProvidersFailed(let primary, let fallback, let errors):
            let fallbackName = fallback?.providerName ?? "fallback AI"
            let details = errors.map { error in
                if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                    return localized
                }
                return error.localizedDescription
            }.joined(separator: " • ")
            return "AI agent failed: \(primary.providerName) and \(fallbackName) could not generate this recap\(details.isEmpty ? "" : " (\(details))"). Please check the connection/API keys and try re-recap."
        }
    }
}

enum LocalEnvironment {
    static func value(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }

        for url in candidateURLs() {
            guard let raw = try? String(contentsOf: url, encoding: .utf8),
                  let value = parse(raw)[key],
                  !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: ".env", withExtension: nil) {
            urls.append(bundled)
        }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))
        return urls
    }

    private static func parse(_ raw: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
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
        let body = segments.map {
            "[\($0.index) @\(Int($0.timestamp))s] [\($0.label.rawValue)] \($0.text)"
        }.joined(separator: "\n")
        let system = """
        You are Recaply's note-taking engine. Summarize this \(tag.rawValue) transcript.
        Return JSON ONLY with this exact schema:
        {"overview":"...","actionItems":["..."],"decisions":["..."],"keyPoints":["..."]}.
        Rules:
        - Preserve the transcript language. If the transcript is Indonesian, answer in Indonesian; if Japanese, answer in Japanese; if mixed, use the dominant language.
        - Do not invent facts, names, dates, deadlines, tasks, or decisions that are not stated.
        - overview must be 1-2 concise sentences explaining the actual topic and outcome, not a raw transcript excerpt.
        - keyPoints must be 3-6 distinct, useful bullets about the material. Do not duplicate actionItems or decisions.
        - actionItems must contain only explicit follow-up tasks. Use [] if none are stated.
        - decisions must contain only explicit decisions/conclusions. Use [] if none are stated.
        - Ignore filler, repeated live-caption fragments, false starts, and recognition noise.
        """
        return [LLMMessage(role: "system", content: system), LLMMessage(role: "user", content: body)]
    }

    static func recordingQuestion(context: String, question: String) -> [LLMMessage] {
        let system = """
        You are Recaply's recording Q&A assistant. Answer questions using ONLY the provided recording context.
        Rules:
        - Preserve the user's language when possible.
        - If the answer is not in the recording context, say that it was not mentioned in the recording.
        - Do not invent facts, names, tasks, dates, deadlines, or decisions.
        - Be concise, but include useful supporting details from the transcript.
        - If relevant, mention timestamps from transcript lines like [03:12].
        """
        let user = """
        Recording context:
        \(context)

        Question:
        \(question)
        """
        return [LLMMessage(role: "system", content: system), LLMMessage(role: "user", content: user)]
    }
}
