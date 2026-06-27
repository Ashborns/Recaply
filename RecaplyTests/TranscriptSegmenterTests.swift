import XCTest
@testable import Recaply

final class TranscriptSegmenterTests: XCTestCase {
    func testSplitsIntoSentencesWithTimestamps() {
        let pieces: [(text: String, time: TimeInterval)] = [
            ("Hello there.", 0.0),
            ("How are you today?", 1.2),
            ("I am fine!", 2.8)
        ]

        let segments = TranscriptSegmenter.segment(pieces)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].text, "Hello there.")
        XCTAssertEqual(segments[0].timestamp, 0.0)
        XCTAssertEqual(segments[2].index, 2)
    }

    func testMergesRunOnFragments() {
        let pieces = [(text: "so then we", time: 0.0), (text: "decided to ship", time: 1.0)]

        let segments = TranscriptSegmenter.segment(pieces)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "so then we decided to ship")
        XCTAssertEqual(segments[0].timestamp, 0.0)
    }
}
