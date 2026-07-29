import XCTest
@testable import LimitsCore

final class AppRefreshGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func policy() -> PollingPolicy {
        let fixedNow = now
        return PollingPolicy(clock: { fixedNow })
    }

    func testAllowedWhenNothingBlocks() {
        let decision = AppRefreshGate.evaluate(
            trigger: .manualRefresh,
            lastFetchAt: nil,
            state: .idle,
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .allowed)
    }

    func testTooSoonWhenWithinManualMinimumInterval() {
        let lastFetchAt = now.addingTimeInterval(-10) // manual minimum is 60s
        let decision = AppRefreshGate.evaluate(
            trigger: .manualRefresh,
            lastFetchAt: lastFetchAt,
            state: .idle,
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .tooSoon(retryAt: lastFetchAt.addingTimeInterval(PollingPolicy.minimumManualInterval)))
    }

    func testTooSoonWhenWithinScheduledMinimumInterval() {
        let lastFetchAt = now.addingTimeInterval(-60) // scheduled minimum is 15 min
        let decision = AppRefreshGate.evaluate(
            trigger: .scheduled,
            lastFetchAt: lastFetchAt,
            state: .idle,
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .tooSoon(retryAt: lastFetchAt.addingTimeInterval(PollingPolicy.minimumScheduledInterval)))
    }

    func testBackoffReportsRetryAt() {
        let retryAt = now.addingTimeInterval(120)
        let decision = AppRefreshGate.evaluate(
            trigger: .manualRefresh,
            lastFetchAt: nil,
            state: .backoff(until: retryAt, consecutiveFailures: 2),
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .backoff(retryAt: retryAt))
    }

    func testAllowedOnceBackoffWindowHasPassed() {
        let retryAt = now.addingTimeInterval(-1)
        let decision = AppRefreshGate.evaluate(
            trigger: .manualRefresh,
            lastFetchAt: nil,
            state: .backoff(until: retryAt, consecutiveFailures: 2),
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .allowed)
    }

    func testNeedsReconnectBlocksRegardlessOfTiming() {
        let decision = AppRefreshGate.evaluate(
            trigger: .manualRefresh,
            lastFetchAt: nil,
            state: .needsReconnect,
            policy: policy(),
            now: now
        )
        XCTAssertEqual(decision, .needsReconnect)
    }
}
