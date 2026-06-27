import Foundation

final class TranscriptEnhancementService {
    static let shared = TranscriptEnhancementService()

    private let primary: LLMProviding
    private let fallback: LLMProviding

    init(primary: LLMProviding = LLMClient.shared, fallback: LLMProviding = DeepseekClient.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func enhance(segments: [TranscriptSegmentModel], tag: SessionTag) async -> EnhancedTranscriptPayload {
        let messages = PromptBuilder.enhancement(segments: segments, tag: tag)
        if let payload = try? await requestPayload(from: primary, messages: messages) { return payload }
        if let payload = try? await requestPayload(from: fallback, messages: messages) { return payload }
        return fallbackPayload(for: segments)
    }

    private func requestPayload(from provider: LLMProviding, messages: [LLMMessage]) async throws -> EnhancedTranscriptPayload {
        let raw = try await provider.complete(messages: messages, jsonMode: true)
        return try JSONDecoder().decode(EnhancedTranscriptPayload.self, from: Data(extractJSON(from: raw).utf8))
    }

    private func fallbackPayload(for segments: [TranscriptSegmentModel]) -> EnhancedTranscriptPayload {
        EnhancedTranscriptPayload(
            clean: segments.map { .init(index: $0.index, text: $0.text) },
            polished: [.init(heading: "Transcript", body: segments.map(\.text).joined(separator: " "))]
        )
    }
}

func extractJSON(from raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    let lines = trimmed.components(separatedBy: .newlines)
    let body = lines.dropFirst().dropLast().joined(separator: "\n")
    return body.trimmingCharacters(in: .whitespacesAndNewlines)
}
