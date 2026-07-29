import XCTest
@testable import LimitsCore

final class AppProviderDashboardStateTests: XCTestCase {
    private func makeSnapshot(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            fetchedAt: fetchedAt,
            windows: [LimitWindow(windowKind: .session, percent: 42)]
        )
    }

    func testNotConnectedWhenNoTokens() {
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: false,
            lastSnapshot: nil,
            pollingState: .idle,
            lastOutcome: nil
        )
        XCTAssertEqual(state, .notConnected)
    }

    func testLoadingWhenConnectedButNeverFetched() {
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .idle,
            lastOutcome: nil
        )
        XCTAssertEqual(state, .loading)
    }

    func testContentWhenIdleWithASnapshot() {
        let snapshot = makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .idle,
            lastOutcome: .success
        )
        XCTAssertEqual(state, .content(snapshot: snapshot))
    }

    func testStaleContentOnBackoffWithRateLimitReason() {
        let snapshot = makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let retryAt = Date(timeIntervalSince1970: 1_800_000_120)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 1),
            lastOutcome: .rateLimited(retryAfter: nil)
        )
        XCTAssertEqual(state, .staleContent(snapshot: snapshot, reason: .rateLimited, retryAt: retryAt))
    }

    func testStaleContentOnBackoffWithNetworkErrorReason() {
        let snapshot = makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let retryAt = Date(timeIntervalSince1970: 1_800_000_030)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 1),
            lastOutcome: .otherFailure
        )
        XCTAssertEqual(state, .staleContent(snapshot: snapshot, reason: .networkError, retryAt: retryAt))
    }

    func testBlockedNoDataWhenBackingOffWithoutEverHavingFetched() {
        let retryAt = Date(timeIntervalSince1970: 1_800_000_030)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 2),
            lastOutcome: .rateLimited(retryAfter: 30)
        )
        XCTAssertEqual(state, .blockedNoData(reason: .rateLimited, retryAt: retryAt))
    }

    func testNeedsReconnectKeepsLastSnapshotVisible() {
        let snapshot = makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized
        )
        XCTAssertEqual(state, .needsReconnect(lastSnapshot: snapshot))
    }

    func testNeedsReconnectWithoutAnyPriorSnapshot() {
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized
        )
        XCTAssertEqual(state, .needsReconnect(lastSnapshot: nil))
    }

    func testNotConnectedTakesPriorityRegardlessOfPollingState() {
        // Defensive: even if a stale PollingState/snapshot were left lying around
        // after a disconnect, `isConnected: false` must always win.
        let snapshot = makeSnapshot(fetchedAt: Date())
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: false,
            lastSnapshot: snapshot,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized
        )
        XCTAssertEqual(state, .notConnected)
    }
}
