import XCTest
@testable import LimitsCore

final class ClaudeUsageClientTests: XCTestCase {
    private let fixedClock: () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - Real fixture

    func testDecodesRealFixtureExactly() async throws {
        let data = try FixtureLoader.load("claude-usage")
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.ok(data), clock: fixedClock)

        let result = await client.fetchUsage(accessToken: "token")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.fetchedAt, fixedClock())

        // limits[] must be preferred over the five_hour/seven_day root fallback —
        // both are present in the fixture, so this also proves we didn't
        // accidentally use the fallback.
        XCTAssertEqual(snapshot.windows.count, 2)

        let session = try XCTUnwrap(snapshot.windows.first { $0.windowKind == .session })
        XCTAssertEqual(session.rawKind, "session")
        XCTAssertEqual(session.percent, 0)
        XCTAssertEqual(session.severity, "normal")
        XCTAssertNil(session.resetsAt, "resets_at: null must map to nil, not an error")
        XCTAssertEqual(session.isActive, false)

        let weekly = try XCTUnwrap(snapshot.windows.first { $0.windowKind == .weekly })
        XCTAssertEqual(weekly.rawKind, "weekly_all")
        XCTAssertEqual(weekly.percent, 8)
        XCTAssertEqual(weekly.severity, "normal")
        XCTAssertEqual(weekly.isActive, true)
        let resetsAt = try XCTUnwrap(weekly.resetsAt)
        XCTAssertEqual(resetsAt, try XCTUnwrap(FlexibleISO8601.parse("2026-08-04T17:59:59.981775+00:00")))

        let extraUsage = try XCTUnwrap(snapshot.extraUsage)
        XCTAssertEqual(extraUsage.isEnabled, false)
        XCTAssertEqual(extraUsage.monthlyLimit, 16000)
        XCTAssertEqual(extraUsage.usedCredits, 15558)
        XCTAssertEqual(extraUsage.utilizationPercent!, 97.2375, accuracy: 0.0001)
        XCTAssertEqual(extraUsage.currency, "AUD")
        XCTAssertEqual(extraUsage.spendPercent, 97)
        XCTAssertEqual(extraUsage.spendSeverity, "critical")

        XCTAssertNil(snapshot.resetCredits, "resetCredits is a Codex-only field")
    }

    // MARK: - Fallback to root objects when limits[] is absent/empty

    func testFallsBackToRootWindowsWhenLimitsIsMissing() async throws {
        let json = """
        {
          "five_hour": { "utilization": 12.5, "resets_at": null },
          "seven_day": { "utilization": 40.0, "resets_at": "2026-08-04T17:59:59+00:00" }
        }
        """
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)

        let result = await client.fetchUsage(accessToken: "token")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(snapshot.windows.count, 2)
        let session = try XCTUnwrap(snapshot.windows.first { $0.windowKind == .session })
        XCTAssertEqual(session.percent, 12.5)
        XCTAssertNil(session.resetsAt)
        let weekly = try XCTUnwrap(snapshot.windows.first { $0.windowKind == .weekly })
        XCTAssertEqual(weekly.percent, 40.0)
        XCTAssertNotNil(weekly.resetsAt)
    }

    func testFallsBackWhenLimitsIsAnEmptyArray() async throws {
        let json = """
        { "five_hour": { "utilization": 1.0, "resets_at": null }, "limits": [] }
        """
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)

        let result = await client.fetchUsage(accessToken: "token")
        guard case .success(let snapshot) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.count, 1)
    }

    // MARK: - Tolerance

    func testUnknownTopLevelKeysAreIgnoredNotFatal() async throws {
        // Exercises the same tolerance as the real fixture's junk keys
        // (tangelo, iguana_necktie...) with a minimal, controlled example.
        let json = """
        { "limits": [], "tangelo": null, "iguana_necktie": { "whatever": 1 } }
        """
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.ok(Data(json.utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        guard case .success(let snapshot) = result else {
            return XCTFail("unknown keys must never cause a decode failure, got \(result)")
        }
        XCTAssertEqual(snapshot.windows.count, 0)
    }

    // MARK: - HTTP error paths

    func testMalformedJSONIsReportedAsDecodingFailureNotACrash() async {
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.ok(Data("not json {{{".utf8)), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.decoding(endpoint: "api/oauth/usage")))
    }

    func test401IsReportedAsUnauthorized() async {
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.status(401), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.unauthorized(endpoint: "api/oauth/usage")))
    }

    func test429WithRetryAfterIsReported() async {
        let client = ClaudeUsageClient(
            httpClient: StubHTTPClient.status(429, headers: ["Retry-After": "30"]),
            clock: fixedClock
        )
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.rateLimited(endpoint: "api/oauth/usage", retryAfter: 30)))
    }

    func test429WithoutRetryAfterIsReportedWithNilRetryAfter() async {
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.status(429), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.rateLimited(endpoint: "api/oauth/usage", retryAfter: nil)))
    }

    func testOtherHTTPStatusIsReported() async {
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.status(500), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.httpStatus(endpoint: "api/oauth/usage", status: 500)))
    }

    func testTransportFailureIsReported() async {
        let client = ClaudeUsageClient(httpClient: StubHTTPClient.transportFailure("offline"), clock: fixedClock)
        let result = await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result, .failure(.transport(endpoint: "api/oauth/usage", reason: "offline")))
    }
}
