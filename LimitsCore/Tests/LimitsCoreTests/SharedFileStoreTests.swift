import XCTest
@testable import LimitsCore

/// `SharedFileStore` accepts an injected container URL specifically so it can be
/// exercised here with a disposable temp directory standing in for the real App Group
/// container — the CI runner (macOS, no App Group entitlement) can't resolve a real
/// one, but the store's logic (encode/write, decode/read, error mapping) is otherwise
/// identical to what runs on-device.
final class SharedFileStoreTests: XCTestCase {
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

    func testWriteThenReadRoundTripsThePayload() {
        let store = SharedFileStore(containerURL: tempContainer)
        let payload = SharedPayload(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), writeCount: 3)

        guard case .ok = store.write(payload) else {
            return XCTFail("write should succeed against a writable temp directory")
        }

        switch store.read() {
        case .ok(let readBack):
            XCTAssertEqual(readBack, payload)
        case .failure(let reason):
            XCTFail("expected a successful read, got failure: \(reason)")
        }
    }

    func testReadFailsExplicitlyWhenFileIsMissing() {
        let store = SharedFileStore(containerURL: tempContainer)

        switch store.read() {
        case .ok:
            XCTFail("read should fail when the file was never written")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testReadFailsExplicitlyOnCorruptedJSON() throws {
        let store = SharedFileStore(containerURL: tempContainer)
        let fileURL = tempContainer.appendingPathComponent("shared-payload.json")
        try Data("not valid json {{{".utf8).write(to: fileURL)

        switch store.read() {
        case .ok:
            XCTFail("read should fail on corrupted JSON, not decode garbage")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testReadFailsExplicitlyWhenContainerURLIsNil() {
        let store = SharedFileStore(containerURL: nil)

        switch store.read() {
        case .ok:
            XCTFail("a nil container URL (entitlement missing) must never look like success")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testWriteFailsExplicitlyWhenContainerURLIsNil() {
        let store = SharedFileStore(containerURL: nil)
        let payload = SharedPayload(updatedAt: Date(), writeCount: 1)

        switch store.write(payload) {
        case .ok:
            XCTFail("a nil container URL (entitlement missing) must never look like success")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }
}
