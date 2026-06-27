import Foundation

final class SummarizationService {
    static let shared = SummarizationService()

    private let primary: LLMProviding
    private let fallback: LLMProviding

    init(primary: LLMProviding = LLMClient.shared, fallback: LLMProviding = DeepseekClient.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func summarize(segments: [TranscriptSegmentModel], tag: SessionTag) async throws -> SummaryPayload {
        let messages = PromptBuilder.summary(segments: segments, tag: tag)
        if let payload = try? await requestPayload(from: primary, messages: messages) { return payload }
        return try await requestPayload(from: fallback, messages: messages)
    }

    private func requestPayload(from provider: LLMProviding, messages: [LLMMessage]) async throws -> SummaryPayload {
        let raw = try await provider.complete(messages: messages, jsonMode: true)
        return try JSONDecoder().decode(SummaryPayload.self, from: Data(extractJSON(from: raw).utf8))
    }
}
