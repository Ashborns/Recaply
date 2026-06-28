import Foundation

final class SummarizationService {
    static let shared = SummarizationService()

    private let primary: LLMProviding
    private let fallback: LLMProviding?

    init(primary: LLMProviding = GroqLLMClient.shared, fallback: LLMProviding? = LLMClient.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func summarize(segments: [TranscriptSegmentModel], tag: SessionTag) async throws -> SummaryPayload {
        try await summarizeWithDiagnostics(segments: segments, tag: tag).payload
    }

    func summarizeWithDiagnostics(segments: [TranscriptSegmentModel], tag: SessionTag) async throws -> AIServiceResult<SummaryPayload> {
        let messages = PromptBuilder.summary(segments: segments, tag: tag)
        do {
            return AIServiceResult(payload: try await requestPayload(from: primary, messages: messages), warning: nil)
        } catch {
            var errors = [error]
            if let fallback {
                do {
                    let payload = try await requestPayload(from: fallback, messages: messages)
                    return AIServiceResult(
                        payload: payload,
                        warning: AIServiceWarning.recoveredWithFallback(primary: primary, fallback: fallback, error: error)
                    )
                } catch {
                    errors.append(error)
                }
            }
            throw AIProviderFailure.allProvidersFailed(primary: primary, fallback: fallback, errors: errors)
        }
    }

    private func requestPayload(from provider: LLMProviding, messages: [LLMMessage]) async throws -> SummaryPayload {
        let raw = try await provider.complete(messages: messages, jsonMode: true)
        return try JSONDecoder().decode(SummaryPayload.self, from: Data(extractJSON(from: raw).utf8))
    }
}
