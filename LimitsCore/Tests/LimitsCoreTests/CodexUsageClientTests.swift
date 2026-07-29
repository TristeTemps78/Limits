import XCTest
@testable import LimitsCore

final class CodexUsageClientTests: XCTestCase {
    private let fixedClock: () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - Real fixtures

    /// The critical case: on this real capture (a Plus-plan account),
    /// `primary_window` is the **weekly** window (604 800s) and `secondary_window`
    /// is absent. A "primary = 5h" implementation would classify this as a session
    /// window and show a wrong-but-plausible number — this test fails loudly if that
    /// regresses.
    func testDecodesRealUsageFixtureAndClassifiesPrimaryWindowAsWeeklyNotSession() async throws {
        let data = try FixtureLoader.load("codex-usage")
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(data), clock: fixedClock)

        let result = await client.fetchUsage(accessToken: "token", accountID: "account")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.windows.count, 1, "secondary_window is null in this fixture — must not be invented")

        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.windowKind, .weekly, "604800s must classify as weekly regardless of being 'primary'")
        XCTAssertEqual(window.windowSeconds, 604_800)
        XCTAssertEqual(window.percent, 9)
        XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 1_785_904_838))

        let resetCredits = try XCTUnwrap(snapshot.resetCredits)
        XCTAssertEqual(resetCredits.availableCount, 0)
        XCTAssertEqual(resetCredits.applicableAvailableCount, 0)
        XCTAssertNil(resetCredits.totalEarnedCount, "only the dedicated endpoint provides total_earned_count")

        XCTAssertNil(snapshot.extraUsage, "extraUsage is a Claude-only field")
    }

    func testDecodesRealResetCreditsFixture() async throws {
        let data = try FixtureLoader.load("codex-credits")
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(data), clock: fixedClock)

        let result = await client.fetchResetCredits(accessToken: "token", accountID: "account")
        guard case .success(let credit) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(credit.availableCount, 0)
        XCTAssertEqual(credit.totalEarnedCount, 0)
        XCTAssertEqual(credit.creditCount, 0, "credits: [] in every real capture we have")
        XCTAssertNil(credit.applicableAvailableCount, "only the embedded wham/usage summary provides this field")
    }

    // MARK: - Absent windows

    func testBothWindowsAbsentProducesNoWindowsNotACrash() async throws {
        let json = """
        { "rate_limit": { "primary_window": null, "secondary_window": null } }
        """
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.count, 0)
    }

    func testUnrecognizedDurationClassifiesAsUnknownNotACrash() async throws {
        let json = """
        { "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 3600, "reset_at": 1000 } } }
        """
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.first?.windowKind, .unknown)
    }

    // MARK: - Alias tolerance (PLAN.md §2.2) — synthetic, unverified by any real
    // capture. Documents the intended tolerance without pretending it's proven.

    func testAliasTopLevelWindowsAreAcceptedWhenRateLimitIsAbsent() async throws {
        let json = """
        {
          "five_hour_limit": { "used_percent": 20, "limit_window_seconds": 18000, "reset_at": 1000 },
          "weekly_limit": { "used_percent": 30, "limit_window_seconds": 604800, "resets_in_seconds": 500 }
        }
        """
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertTrue(snapshot.windows.contains { $0.windowKind == .session && $0.percent == 20 })
        let weekly = try XCTUnwrap(snapshot.windows.first { $0.windowKind == .weekly })
        XCTAssertEqual(weekly.percent, 30)
        // "resets_in_seconds" (alias for reset_after_seconds) must still produce a
        // resetsAt, relative to fetchedAt since there's no epoch in this payload.
        XCTAssertEqual(weekly.resetsAt, fixedClock().addingTimeInterval(500))
    }

    func testResetAfterSecondsIsUsedWhenResetAtEpochIsAbsent() async throws {
        let json = """
        { "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 18000, "reset_after_seconds": 120 } } }
        """
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.first?.resetsAt, fixedClock().addingTimeInterval(120))
    }

    func testRateLimitTakesPriorityOverAliasWhenBothPresent() async throws {
        let json = """
        {
          "rate_limit": { "primary_window": { "used_percent": 1, "limit_window_seconds": 604800 } },
          "five_hour_limit": { "used_percent": 99, "limit_window_seconds": 18000 }
        }
        """
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.percent, 1)
    }

    // MARK: - HTTP error paths

    func testMalformedJSONIsReportedAsDecodingFailure() async {
        let client = CodexUsageClient(httpClient: StubHTTPClient.ok(Data("{{{".utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        XCTAssertEqual(result, .failure(.decoding(endpoint: "wham/usage")))
    }

    func test401IsReportedAsUnauthorized() async {
        let client = CodexUsageClient(httpClient: StubHTTPClient.status(401), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        XCTAssertEqual(result, .failure(.unauthorized(endpoint: "wham/usage")))
    }

    func test429WithRetryAfterIsReported() async {
        let client = CodexUsageClient(httpClient: StubHTTPClient.status(429, headers: ["Retry-After": "12"]), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "t", accountID: "a")
        XCTAssertEqual(result, .failure(.rateLimited(endpoint: "wham/usage", retryAfter: 12)))
    }

    func testResetCreditsEndpointReports401Separately() async {
        let client = CodexUsageClient(httpClient: StubHTTPClient.status(401), clock: fixedClock)
        let result = await client.fetchResetCredits(accessToken: "t", accountID: "a")
        XCTAssertEqual(result, .failure(.unauthorized(endpoint: "wham/rate-limit-reset-credits")))
    }
}
