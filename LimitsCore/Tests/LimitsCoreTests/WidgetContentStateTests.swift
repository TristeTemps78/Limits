import XCTest
@testable import LimitsCore

final class WidgetContentStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Read failures pass through untouched

    func testReadFailurePropagatesTheExactError() {
        let state = WidgetContentStateBuilder.build(result: .failure(.containerUnavailable), now: now)
        XCTAssertEqual(state, .readFailed(.containerUnavailable))
    }

    func testAllSnapshotStoreErrorCasesPropagate() {
        let errors: [SnapshotStoreError] = [
            .containerUnavailable, .fileNotFound,
            .unsupportedSchemaVersion(found: 99, expected: 1), .corrupted, .encodingFailed
        ]
        for error in errors {
            XCTAssertEqual(WidgetContentStateBuilder.build(result: .failure(error), now: now), .readFailed(error))
        }
    }

    // MARK: - Never connected

    func testNilProvidersWithNilStatusIsNotConnected() {
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: nil, codex: nil)
        XCTAssertEqual(WidgetContentStateBuilder.build(result: .success(snapshots), now: now), .notConnected)
    }

    func testNilProvidersWithExplicitNotConnectedStatusIsNotConnected() {
        let snapshots = SharedUsageSnapshots(
            updatedAt: now, claude: nil, codex: nil, claudeStatus: .notConnected, codexStatus: .notConnected
        )
        XCTAssertEqual(WidgetContentStateBuilder.build(result: .success(snapshots), now: now), .notConnected)
    }

    func testNeedsReconnectWithNoSnapshotYetIsNotTreatedAsNeverConnected() {
        // First login attempt failed outright: no `UsageSnapshot` exists, but the
        // status is a real signal, not silence — must not collapse into `.notConnected`.
        let snapshots = SharedUsageSnapshots(
            updatedAt: now, claude: nil, codex: nil, claudeStatus: .needsReconnect, codexStatus: .notConnected
        )
        guard case .ready(_, _, let reconnectNeeded) = WidgetContentStateBuilder.build(result: .success(snapshots), now: now) else {
            return XCTFail("expected .ready with a reconnect flag, not .notConnected")
        }
        XCTAssertEqual(reconnectNeeded, [.claude])
    }

    // MARK: - Ready: freshness + reconnect flags

    func testReadyCarriesFreshnessLevel() {
        guard case .ready(_, let freshness, _) = WidgetContentStateBuilder.build(result: .success(SampleSnapshots.bothConnected), now: now) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(freshness, .fresh)
    }

    func testStaleSnapshotIsFlaggedStale() {
        guard case .ready(_, let freshness, _) = WidgetContentStateBuilder.build(result: .success(SampleSnapshots.stale), now: SampleSnapshots.referenceNow) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(freshness, .stale)
    }

    func testNeedsReconnectListsOnlyTheAffectedProviders() {
        guard case .ready(_, _, let reconnectNeeded) = WidgetContentStateBuilder.build(
            result: .success(SampleSnapshots.claudeNeedsReconnect), now: SampleSnapshots.referenceNow
        ) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(reconnectNeeded, [.claude])
    }

    func testConnectedStatusNeverAppearsInReconnectNeeded() {
        guard case .ready(_, _, let reconnectNeeded) = WidgetContentStateBuilder.build(result: .success(SampleSnapshots.bothConnected), now: now) else {
            return XCTFail("expected .ready")
        }
        XCTAssertTrue(reconnectNeeded.isEmpty)
    }

    func testLastKnownSnapshotIsStillReturnedAlongsideReconnectFlag() {
        // PLAN.md §6: the last snapshot must always stay visible, even when a
        // provider needs reconnecting.
        guard case .ready(let snapshots, _, let reconnectNeeded) = WidgetContentStateBuilder.build(
            result: .success(SampleSnapshots.claudeNeedsReconnect), now: SampleSnapshots.referenceNow
        ) else {
            return XCTFail("expected .ready")
        }
        XCTAssertNotNil(snapshots.claude, "the stale-but-last-known Claude snapshot must not be dropped")
        XCTAssertEqual(reconnectNeeded, [.claude])
    }
}
