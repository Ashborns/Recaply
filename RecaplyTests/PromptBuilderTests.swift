import XCTest
@testable import Recaply

final class PromptBuilderTests: XCTestCase {
    func testEnhancementPromptIncludesTimestampsLabelsAndSchema() {
        let segment = TranscriptSegmentModel(index: 0, text: "hi there.", timestamp: 3, label: .question, confidence: 0.9)

        let messages = PromptBuilder.enhancement(segments: [segment], tag: .meeting)

        XCTAssertTrue(messages[1].content.contains("[0 @3s]"))
        XCTAssertTrue(messages[1].content.contains("[question]"))
        XCTAssertTrue(messages[0].content.contains("\"polished\""))
        XCTAssertTrue(messages[0].content.contains("JSON ONLY"))
    }

    func testSummaryPromptIncludesLabelsAndSchema() {
        let segment = TranscriptSegmentModel(index: 0, text: "ship it.", timestamp: 0, label: .decision, confidence: 0.9)

        let messages = PromptBuilder.summary(segments: [segment], tag: .lecture)

        XCTAssertTrue(messages[1].content.contains("[decision]"))
        XCTAssertTrue(messages[0].content.contains("\"actionItems\""))
        XCTAssertTrue(messages[0].content.contains("lecture"))
    }
}
