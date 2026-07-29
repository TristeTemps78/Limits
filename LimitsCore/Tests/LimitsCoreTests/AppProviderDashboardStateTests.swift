import XCTest
@testable import LimitsCore

final class AppProviderDashboardStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

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
            lastOutcome: nil,
            now: now
        )
        XCTAssertEqual(state, .notConnected)
    }

    func testLoadingWhenConnectedButNeverFetched() {
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .idle,
            lastOutcome: nil,
            now: now
        )
        XCTAssertEqual(state, .loading)
    }

    func testContentWhenIdleWithASnapshot() {
        let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-125))
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .idle,
            lastOutcome: .success,
            now: now
        )
        XCTAssertEqual(state, .content(snapshot: snapshot, freshnessSeconds: 125))
    }

    func testStaleContentOnBackoffWithRateLimitReason() {
        let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-600))
        let retryAt = now.addingTimeInterval(120)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 1),
            lastOutcome: .rateLimited(retryAfter: nil),
            now: now
        )
        XCTAssertEqual(state, .staleContent(snapshot: snapshot, freshnessSeconds: 600, reason: .rateLimited, retryAt: retryAt))
    }

    func testStaleContentOnBackoffWithNetworkErrorReason() {
        let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-60))
        let retryAt = now.addingTimeInterval(30)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 1),
            lastOutcome: .otherFailure,
            now: now
        )
        XCTAssertEqual(state, .staleContent(snapshot: snapshot, freshnessSeconds: 60, reason: .networkError, retryAt: retryAt))
    }

    func testBlockedNoDataWhenBackingOffWithoutEverHavingFetched() {
        let retryAt = now.addingTimeInterval(30)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .backoff(until: retryAt, consecutiveFailures: 2),
            lastOutcome: .rateLimited(retryAfter: 30),
            now: now
        )
        XCTAssertEqual(state, .blockedNoData(reason: .rateLimited, retryAt: retryAt))
    }

    func testNeedsReconnectKeepsLastSnapshotVisible() {
        let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-3600))
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: snapshot,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized,
            now: now
        )
        XCTAssertEqual(state, .needsReconnect(lastSnapshot: snapshot, freshnessSeconds: 3600))
    }

    func testNeedsReconnectWithoutAnyPriorSnapshot() {
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: nil,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized,
            now: now
        )
        XCTAssertEqual(state, .needsReconnect(lastSnapshot: nil, freshnessSeconds: nil))
    }

    func testNotConnectedTakesPriorityRegardlessOfPollingState() {
        // Defensive: even if a stale PollingState/snapshot were left lying around
        // after a disconnect, `isConnected: false` must always win.
        let snapshot = makeSnapshot(fetchedAt: now)
        let state = AppProviderDashboardStateBuilder.build(
            isConnected: false,
            lastSnapshot: snapshot,
            pollingState: .needsReconnect,
            lastOutcome: .unauthorized,
            now: now
        )
        XCTAssertEqual(state, .notConnected)
    }
}
