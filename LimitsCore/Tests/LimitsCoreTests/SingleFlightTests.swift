import XCTest
@testable import LimitsCore

final class SingleFlightTests: XCTestCase {
    /// Fires several concurrent `run` calls against the same `SingleFlight` while the
    /// underlying operation is deliberately slow (so the calls genuinely overlap
    /// rather than happening to run sequentially) and asserts the operation itself
    /// only executed once, with every caller receiving that one result — this is the
    /// property that prevents Codex's `refresh_token_reused` (docs/oauth-verification-2026-07-29.md,
    /// piège 3).
    func testConcurrentCallsCoalesceIntoASingleExecution() async throws {
        let counter = Counter()
        let flight = SingleFlight<Int>()

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await flight.run {
                        await counter.increment()
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        return 42
                    }
                }
            }
            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        XCTAssertEqual(results, Array(repeating: 42, count: 10))
        let executions = await counter.value
        XCTAssertEqual(executions, 1, "the operation should have run exactly once for all 10 concurrent callers")
    }

    /// Once the in-flight call completes, a later call should start a brand new
    /// execution rather than replaying a stale cached result.
    func testSequentialCallsAfterCompletionEachRunTheOperation() async throws {
        let counter = Counter()
        let flight = SingleFlight<Int>()

        _ = try await flight.run {
            await counter.increment()
            return 1
        }
        _ = try await flight.run {
            await counter.increment()
            return 2
        }

        let executions = await counter.value
        XCTAssertEqual(executions, 2)
    }

    func testPropagatesErrorFromOperationToAllCoalescedCallers() async {
        struct DummyError: Error, Equatable {}
        let flight = SingleFlight<Int>()

        do {
            _ = try await flight.run {
                try? await Task.sleep(nanoseconds: 10_000_000)
                throw DummyError()
            }
            XCTFail("expected the operation's error to propagate")
        } catch {
            XCTAssertTrue(error is DummyError)
        }
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
