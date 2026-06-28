import Foundation

final class RecordingQuestionService {
    static let shared = RecordingQuestionService()

    private let primary: LLMProviding
    private let fallback: LLMProviding?

    init(primary: LLMProviding = GroqLLMClient.shared, fallback: LLMProviding? = LLMClient.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func answer(question: String, context: String) async throws -> AIServiceResult<String> {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            return AIServiceResult(payload: "Ask a question about this recording first.", warning: nil)
        }

        let messages = PromptBuilder.recordingQuestion(context: context, question: trimmedQuestion)
        do {
            return AIServiceResult(payload: try await requestAnswer(from: primary, messages: messages), warning: nil)
        } catch {
            var errors = [error]
            if let fallback {
                do {
                    let answer = try await requestAnswer(from: fallback, messages: messages)
                    return AIServiceResult(
                        payload: answer,
                        warning: AIServiceWarning.recoveredWithFallback(primary: primary, fallback: fallback, error: error)
                    )
                } catch {
                    errors.append(error)
                }
            }

            throw AIProviderFailure.allProvidersFailed(primary: primary, fallback: fallback, errors: errors)
        }
    }

    private func requestAnswer(from provider: LLMProviding, messages: [LLMMessage]) async throws -> String {
        let raw = try await provider.complete(messages: messages, jsonMode: false)
        let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw LLMError.emptyChoice }
        return answer
    }
}