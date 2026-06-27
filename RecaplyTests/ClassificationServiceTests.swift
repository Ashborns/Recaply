import XCTest
@testable import Recaply

final class ClassificationServiceTests: XCTestCase {
    func testStubReturnsDiscussionWithZeroConfidence() {
        let service = ClassificationService(provider: StubClassifierProvider())

        let (label, confidence) = service.classify("anything")

        XCTAssertEqual(label, .discussion)
        XCTAssertEqual(confidence, 0.0)
    }

    func testClassifiesSegmentsWithoutChangingOrder() {
        let segments = [
            TranscriptSegmentModel(index: 0, text: "First item.", timestamp: 0),
            TranscriptSegmentModel(index: 1, text: "Second item.", timestamp: 3)
        ]
        let service = ClassificationService(provider: StubClassifierProvider())

        let labeled = service.classify(segments)

        XCTAssertEqual(labeled.map(\.index), [0, 1])
        XCTAssertEqual(labeled.map(\.label), [.discussion, .discussion])
        XCTAssertEqual(labeled.map(\.confidence), [0, 0])
    }
}
