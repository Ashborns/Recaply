import Foundation

final class TranscriptEnhancementService {
    static let shared = TranscriptEnhancementService()

    private let primary: LLMProviding
    private let fallback: LLMProviding?

    init(primary: LLMProviding = LLMClient.shared, fallback: LLMProviding? = GroqLLMClient.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func enhance(segments: [TranscriptSegmentModel], tag: SessionTag) async throws -> EnhancedTranscriptPayload {
        try await enhanceWithDiagnostics(segments: segments, tag: tag).payload
    }

    func enhanceWithDiagnostics(segments: [TranscriptSegmentModel], tag: SessionTag) async throws -> AIServiceResult<EnhancedTranscriptPayload> {
        let messages = PromptBuilder.enhancement(segments: segments, tag: tag)
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

    private func requestPayload(from provider: LLMProviding, messages: [LLMMessage]) async throws -> EnhancedTranscriptPayload {
        let raw = try await provider.complete(messages: messages, jsonMode: true)
        return try JSONDecoder().decode(EnhancedTranscriptPayload.self, from: Data(extractJSON(from: raw).utf8))
    }

}

func extractJSON(from raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    let lines = trimmed.components(separatedBy: .newlines)
    let body = lines.dropFirst().dropLast().joined(separator: "\n")
    return body.trimmingCharacters(in: .whitespacesAndNewlines)
}
