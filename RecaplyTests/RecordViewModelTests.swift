import XCTest
@testable import Recaply

final class RecordViewModelTests: XCTestCase {
    // `@MainActor` because `RecordViewModel` is main-actor-isolated; the assertions
    // below are unchanged from the approved spec (idle → recording → stopping).
    @MainActor
    func testIdleToRecordingToStopping() async throws {
        let vm = RecordViewModel(recorder: StubRecorder(), camera: StubCamera())
        XCTAssertEqual(vm.phase, .idle)
        try? await vm.start(tag: .meeting, title: nil)
        XCTAssertEqual(vm.phase, .recording)
        vm.stop()
        XCTAssertEqual(vm.phase, .stopping)
        XCTAssertNotNil(vm.lastRecording)
    }
}

private final class StubRecorder: RecordingProviding {
    var currentLevel: Float = 0.5
    func start() throws -> URL { URL(fileURLWithPath: "/tmp/rec.m4a") }
    func stop() throws -> (url: URL, duration: TimeInterval) {
        (URL(fileURLWithPath: "/tmp/rec.m4a"), 42)
    }
}

private final class StubCamera: CameraProviding {
    func requestAccess() async -> Bool { true }
    func start() async throws {}
    func stop() -> URL? { nil }
    func waitForFinalization() async {}
}
