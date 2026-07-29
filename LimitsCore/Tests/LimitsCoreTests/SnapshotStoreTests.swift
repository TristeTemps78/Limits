import XCTest
@testable import LimitsCore

final class SnapshotStoreTests: XCTestCase {
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

    private func makeBundle() -> SharedUsageSnapshots {
        SharedUsageSnapshots(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            claude: UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), windows: []),
            codex: nil
        )
    }

    func testWriteThenReadRoundTripsTheSnapshot() {
        let store = SnapshotStore(containerURL: tempContainer)
        let bundle = makeBundle()

        guard case .success = store.write(bundle) else {
            return XCTFail("write should succeed against a writable temp directory")
        }

        switch store.read() {
        case .success(let readBack):
            XCTAssertEqual(readBack, bundle)
        case .failure(let error):
            XCTFail("expected a successful read, got \(error)")
        }
    }

    func testReadFailsExplicitlyWhenFileIsMissing() {
        let store = SnapshotStore(containerURL: tempContainer)
        XCTAssertEqual(store.read(), .failure(.fileNotFound))
    }

    func testReadFailsExplicitlyWhenContainerURLIsNil() {
        let store = SnapshotStore(containerURL: nil)
        XCTAssertEqual(store.read(), .failure(.containerUnavailable))
    }

    func testWriteFailsExplicitlyWhenContainerURLIsNil() {
        let store = SnapshotStore(containerURL: nil)
        XCTAssertEqual(store.write(makeBundle()), .failure(.containerUnavailable))
    }

    func testReadFailsExplicitlyOnCorruptedJSON() throws {
        let store = SnapshotStore(containerURL: tempContainer)
        let fileURL = tempContainer.appendingPathComponent("usage-snapshots.json")
        try Data("not valid json {{{".utf8).write(to: fileURL)

        XCTAssertEqual(store.read(), .failure(.corrupted))
    }

    func testContainerUnavailableAndFileMissingProduceDistinctErrors() {
        // The two must never be confused with each other — one means "entitlement
        // lost at re-signing", the other means "entitlement fine, nothing written
        // yet". Conflating them would misdirect the gate M1 verdict.
        let nilContainerResult = SnapshotStore(containerURL: nil).read()
        let missingFileResult = SnapshotStore(containerURL: tempContainer).read()
        XCTAssertNotEqual(nilContainerResult, missingFileResult)
    }

    func testUnsupportedSchemaVersionIsDetectedWithoutAttemptingAFullDecode() throws {
        let store = SnapshotStore(containerURL: tempContainer)
        let fileURL = tempContainer.appendingPathComponent("usage-snapshots.json")

        // A "future" file: a schema version this binary doesn't know about, and a
        // shape (`totally_new_field`) that would fail a naive full decode anyway —
        // the point is we never get that far, we bail out on the version check.
        let futureJSON = """
        { "schemaVersion": 999, "totally_new_field": { "nested": true } }
        """
        try Data(futureJSON.utf8).write(to: fileURL)

        XCTAssertEqual(
            store.read(),
            .failure(.unsupportedSchemaVersion(found: 999, expected: SharedUsageSnapshots.currentSchemaVersion))
        )
    }

    func testEncodedFileCarriesTheCurrentSchemaVersion() throws {
        let store = SnapshotStore(containerURL: tempContainer)
        _ = store.write(makeBundle())

        let fileURL = tempContainer.appendingPathComponent("usage-snapshots.json")
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["schemaVersion"] as? Int, SharedUsageSnapshots.currentSchemaVersion)
    }
}
