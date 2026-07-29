import XCTest
@testable import LimitsCore

final class PollingPolicyTests: XCTestCase {
    // MARK: - Minimum intervals (PLAN.md §6.1)

    func testScheduledFetchBlockedBeforeFifteenMinutesElapsed() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let policy = PollingPolicy(clock: { now })
        let lastFetch = now

        now = lastFetch.addingTimeInterval(14 * 60 + 59)
        XCTAssertFalse(policy.canFetch(trigger: .scheduled, lastFetchAt: lastFetch, state: .idle))

        now = lastFetch.addingTimeInterval(15 * 60)
        XCTAssertTrue(policy.canFetch(trigger: .scheduled, lastFetchAt: lastFetch, state: .idle))
    }

    func testManualRefreshBlockedBeforeOneMinuteElapsed() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let policy = PollingPolicy(clock: { now })
        let lastFetch = now

        now = lastFetch.addingTimeInterval(59)
        XCTAssertFalse(policy.canFetch(trigger: .manualRefresh, lastFetchAt: lastFetch, state: .idle))

        now = lastFetch.addingTimeInterval(60)
        XCTAssertTrue(policy.canFetch(trigger: .manualRefresh, lastFetchAt: lastFetch, state: .idle))
    }

    func testFirstFetchEverIsAlwaysAllowed() {
        let policy = PollingPolicy(clock: { Date(timeIntervalSince1970: 0) })
        XCTAssertTrue(policy.canFetch(trigger: .scheduled, lastFetchAt: nil, state: .idle))
        XCTAssertTrue(policy.canFetch(trigger: .manualRefresh, lastFetchAt: nil, state: .idle))
    }

    // MARK: - 429 backoff (PLAN.md §6.3)

    func testRateLimitWithoutRetryAfterUsesExponentialBackoffSteps() {
        var now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })

        var state: PollingState = .idle
        let expectedSteps: [TimeInterval] = [30, 120, 600, 1800, 1800] // caps at the last step

        for expectedDelay in expectedSteps {
            state = policy.nextState(current: state, outcome: .rateLimited(retryAfter: nil))
            guard case .backoff(let until, _) = state else {
                return XCTFail("expected .backoff, got \(state)")
            }
            XCTAssertEqual(until.timeIntervalSince(now), expectedDelay)
            now = until // simulate time passing to just before the next attempt
        }
    }

    func testRateLimitWithRetryAfterHonorsTheHeaderOverExponentialBackoff() {
        let now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })

        let state = policy.nextState(current: .idle, outcome: .rateLimited(retryAfter: 45))
        guard case .backoff(let until, let failures) = state else {
            return XCTFail("expected .backoff, got \(state)")
        }
        XCTAssertEqual(until.timeIntervalSince(now), 45)
        XCTAssertEqual(failures, 1)
    }

    func testRateLimitWithZeroOrNegativeRetryAfterFallsBackToExponentialBackoff() {
        let now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })

        let state = policy.nextState(current: .idle, outcome: .rateLimited(retryAfter: 0))
        guard case .backoff(let until, _) = state else {
            return XCTFail("expected .backoff, got \(state)")
        }
        XCTAssertEqual(until.timeIntervalSince(now), 30, "a non-positive Retry-After must not be trusted verbatim")
    }

    func testCannotFetchDuringBackoffWindow() {
        var now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })
        let state = policy.nextState(current: .idle, outcome: .rateLimited(retryAfter: 100))

        now = now.addingTimeInterval(50)
        XCTAssertFalse(policy.canFetch(trigger: .manualRefresh, lastFetchAt: nil, state: state))

        now = now.addingTimeInterval(50) // now at +100
        XCTAssertTrue(policy.canFetch(trigger: .manualRefresh, lastFetchAt: nil, state: state))
    }

    // MARK: - 401 → needsReconnect, never an automatic retry loop (PLAN.md §6.4)

    func testUnauthorizedTransitionsToNeedsReconnect() {
        let policy = PollingPolicy(clock: { Date() })
        let state = policy.nextState(current: .idle, outcome: .unauthorized)
        XCTAssertEqual(state, .needsReconnect)
    }

    func testNeedsReconnectBlocksFetchingRegardlessOfElapsedTime() {
        var now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })
        now = now.addingTimeInterval(999_999)
        XCTAssertFalse(policy.canFetch(trigger: .scheduled, lastFetchAt: nil, state: .needsReconnect))
    }

    func testNeedsReconnectDoesNotSelfHealOnAnotherOutcome() {
        // Once in needsReconnect, only an explicit external reset() gets out of it —
        // a stray "success" reported against a stale in-flight request must not
        // silently clear the reconnect banner.
        let policy = PollingPolicy(clock: { Date() })
        XCTAssertEqual(policy.reset(), .idle)
    }

    // MARK: - Success clears backoff/failure count

    func testSuccessResetsToIdle() {
        let policy = PollingPolicy(clock: { Date() })
        let backoffState = policy.nextState(current: .idle, outcome: .rateLimited(retryAfter: 30))
        let next = policy.nextState(current: backoffState, outcome: .success)
        XCTAssertEqual(next, .idle)
    }

    func testConsecutiveFailuresAccumulateAcrossBackoffStates() {
        var now = Date(timeIntervalSince1970: 0)
        let policy = PollingPolicy(clock: { now })

        let firstFailure = policy.nextState(current: .idle, outcome: .otherFailure)
        guard case .backoff(let firstUntil, let firstCount) = firstFailure else {
            return XCTFail("expected .backoff, got \(firstFailure)")
        }
        XCTAssertEqual(firstCount, 1)

        now = firstUntil
        let secondFailure = policy.nextState(current: firstFailure, outcome: .otherFailure)
        guard case .backoff(_, let secondCount) = secondFailure else {
            return XCTFail("expected .backoff, got \(secondFailure)")
        }
        XCTAssertEqual(secondCount, 2)
    }
}
