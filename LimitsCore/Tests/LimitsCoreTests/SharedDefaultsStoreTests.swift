import XCTest
@testable import LimitsCore

/// Unlike the App Group file container, `UserDefaults(suiteName:)` doesn't require a
/// real entitlement to open on macOS, so these tests exercise the store against a
/// genuine (disposable) suite rather than a fake — closer to the real behavior on
/// device, without needing an injected-URL indirection like `SharedFileStore`.
final class SharedDefaultsStoreTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LimitsCoreTests.\(UUID().uuidString)"
        suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testWriteThenReadRoundTripsThePayload() {
        let store = SharedDefaultsStore(defaults: suite)
        let payload = SharedPayload(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), writeCount: 7)

        guard case .ok = store.write(payload) else {
            return XCTFail("write should succeed against a real UserDefaults suite")
        }

        switch store.read() {
        case .ok(let readBack):
            XCTAssertEqual(readBack, payload)
        case .failure(let reason):
            XCTFail("expected a successful read, got failure: \(reason)")
        }
    }

    func testReadFailsExplicitlyWhenKeyIsMissing() {
        let store = SharedDefaultsStore(defaults: suite)

        switch store.read() {
        case .ok:
            XCTFail("read should fail when the key was never written")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testReadAndWriteFailExplicitlyWhenDefaultsIsNil() {
        let store = SharedDefaultsStore(defaults: nil)

        switch store.write(SharedPayload(updatedAt: Date(), writeCount: 1)) {
        case .ok:
            XCTFail("a nil UserDefaults (App Group missing) must never look like success")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }

        switch store.read() {
        case .ok:
            XCTFail("a nil UserDefaults (App Group missing) must never look like success")
        case .failure(let reason):
            XCTAssertFalse(reason.isEmpty)
        }
    }
}
