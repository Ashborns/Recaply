import XCTest
@testable import Recaply

final class EnhancementDecodingTests: XCTestCase {
    func testDecodesCleanAndPolishedTopics() throws {
        let json = #"""
        {"clean":[{"index":0,"text":"Send the PRD Friday."}],
         "polished":[{"heading":"Scope","body":"We agreed on the plan."}]}
        """#.data(using: .utf8)!

        let payload = try JSONDecoder().decode(EnhancedTranscriptPayload.self, from: json)

        XCTAssertEqual(payload.clean.first?.index, 0)
        XCTAssertEqual(payload.clean.first?.text, "Send the PRD Friday.")
        XCTAssertEqual(payload.polished.first?.heading, "Scope")
    }

    func testExtractsFencedJSON() throws {
        let raw = """
        ```json
        {"clean":[{"index":1,"text":"Clean text."}],"polished":[{"heading":"Topic","body":"Body."}]}
        ```
        """

        let json = extractJSON(from: raw)
        let payload = try JSONDecoder().decode(EnhancedTranscriptPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.clean.first?.index, 1)
        XCTAssertEqual(payload.polished.first?.body, "Body.")
    }
}
