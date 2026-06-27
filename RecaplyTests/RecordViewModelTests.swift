import XCTest
@testable import Recaply

final class RecordViewModelTests: XCTestCase {
    func testIdleToRecordingToStopping() {
        let vm = RecordViewModel(recorder: StubRecorder())
        XCTAssertEqual(vm.phase, .idle)
        try? vm.start(tag: .meeting, title: nil)
        XCTAssertEqual(vm.phase, .recording)
        vm.stop()
        XCTAssertEqual(vm.phase, .stopping)
        XCTAssertNotNil(vm.lastRecording)
    }
}

private final class StubRecorder: RecordingProviding {
    var currentLevel: Float = 0.5
    func start() throws -> URL { URL(string: "file:///tmp/rec.m4a")! }
    func stop() throws -> (url: URL, duration: TimeInterval) {
        (URL(string: "file:///tmp/rec.m4a")!, 42)
    }
}
