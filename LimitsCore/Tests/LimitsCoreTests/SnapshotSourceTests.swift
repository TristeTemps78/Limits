import XCTest
@testable import LimitsCore

final class SnapshotSourceTests: XCTestCase {
    private var tempContainer: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempContainer = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempContainer, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempContainer)
        tempContainer = nil
        try super.tearDownWithError()
    }

    func testAppGroupSnapshotSourceDelegatesToTheInjectedStore() {
        let bundle = SharedUsageSnapshots(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            claude: nil,
            codex: nil
        )
        let store = SnapshotStore(containerURL: tempContainer)
        _ = store.write(bundle)

        let source = AppGroupSnapshotSource(store: store)
        switch source.loadSnapshots() {
        case .success(let readBack):
            XCTAssertEqual(readBack, bundle)
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testAppGroupSnapshotSourceConvenienceInitBuildsItsOwnStore() {
        let source = AppGroupSnapshotSource(containerURL: nil)
        XCTAssertEqual(source.loadSnapshots(), .failure(.containerUnavailable))
    }

    /// A future implementation ("the widget fetches itself") only needs to conform
    /// to `SnapshotSource` — this proves the protocol is narrow enough for a second,
    /// entirely different backing (no App Group, no file) to satisfy it too.
    func testProtocolIsSatisfiableByANonFileBackedImplementation() {
        struct InMemorySnapshotSource: SnapshotSource {
            let result: Result<SharedUsageSnapshots, SnapshotStoreError>
            func loadSnapshots() -> Result<SharedUsageSnapshots, SnapshotStoreError> { result }
        }

        let bundle = SharedUsageSnapshots(updatedAt: Date(timeIntervalSince1970: 0), claude: nil, codex: nil)
        let source: SnapshotSource = InMemorySnapshotSource(result: .success(bundle))
        XCTAssertEqual(source.loadSnapshots(), .success(bundle))
    }
}
