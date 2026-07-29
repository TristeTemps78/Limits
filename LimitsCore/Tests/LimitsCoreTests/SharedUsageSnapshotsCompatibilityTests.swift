import XCTest
@testable import LimitsCore

/// `claudeStatus`/`codexStatus` (T2.3) were added to `SharedUsageSnapshots` after T2.1
/// shipped, without a `schemaVersion` bump — this proves that choice was safe: a JSON
/// file written by the pre-T2.3 shape still decodes cleanly, with the new fields `nil`,
/// never a thrown error. This is exactly the scenario `SnapshotStore`'s schema-version
/// probe exists for in the *breaking* case; this one is deliberately non-breaking.
final class SharedUsageSnapshotsCompatibilityTests: XCTestCase {
    func testDecodingJSONWithoutTheConnectionStatusFieldsSucceedsWithNilStatuses() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "updatedAt": "2026-07-29T00:00:00Z",
          "claude": null,
          "codex": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SharedUsageSnapshots.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.claudeStatus)
        XCTAssertNil(decoded.codexStatus)
    }

    func testEncodeDecodeRoundTripsTheNewFieldsWhenPresent() throws {
        let original = SharedUsageSnapshots(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            claude: nil,
            codex: nil,
            claudeStatus: .needsReconnect,
            codexStatus: .connected
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SharedUsageSnapshots.self, from: try encoder.encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.claudeStatus, .needsReconnect)
        XCTAssertEqual(decoded.codexStatus, .connected)
    }

    func testNilStatusIsTreatedAsNotConnectedNeverAsConnected() {
        // The behavioral point of the compatibility guarantee above: an old file read
        // by a new binary must not make a provider look silently "connected".
        let legacy = SharedUsageSnapshots(updatedAt: Date(), claude: nil, codex: nil)
        XCTAssertEqual(WidgetContentStateBuilder.build(result: .success(legacy), now: Date()), .notConnected)
    }
}
