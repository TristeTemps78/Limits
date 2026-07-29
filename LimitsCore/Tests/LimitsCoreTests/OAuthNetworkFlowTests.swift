import XCTest
@testable import LimitsCore

/// Exercises `ClaudeOAuth`/`CodexOAuth`'s `exchange`/`refresh` end to end through a
/// `StubOAuthTransport` — the request-construction tests in `ClaudeOAuthTests`/
/// `CodexOAuthTests` never actually call these; this file is what protects the
/// `HTTPURLResponse` status branching and, for Codex, the failure-classifier wiring
/// *inside* `refresh` (as opposed to the classifier tested standalone) from a silent
/// regression. No real network call anywhere here.
final class OAuthNetworkFlowTests: XCTestCase {
    struct DummyTransportError: Error {}

    // MARK: - ClaudeOAuth.exchange

    func testClaudeExchangeSucceedsOn2xx() async {
        let body = Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await ClaudeOAuth.exchange(code: "c", state: "s", codeVerifier: "v", transport: transport)

        switch result {
        case .success(let response):
            XCTAssertEqual(response.accessToken, "a")
            XCTAssertEqual(response.refreshToken, "r")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testClaudeExchangeFailsOnHTTPError() async {
        let transport = StubOAuthTransport(statusCode: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))

        let result = await ClaudeOAuth.exchange(code: "c", state: "s", codeVerifier: "v", transport: transport)

        switch result {
        case .success:
            XCTFail("expected failure on HTTP 400")
        case .failure(let error):
            XCTAssertEqual(error, .httpStatus(400, endpoint: "token endpoint"))
        }
    }

    func testClaudeExchangeFailsOnUnreadableBody() async {
        let transport = StubOAuthTransport(statusCode: 200, body: Data("not json at all".utf8))

        let result = await ClaudeOAuth.exchange(code: "c", state: "s", codeVerifier: "v", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a decoding failure on garbage body")
        case .failure(let error):
            XCTAssertEqual(error, .decodingFailed(endpoint: "token endpoint"))
        }
    }

    func testClaudeExchangeFailsOnTransportError() async {
        let transport = StubOAuthTransport(throwing: DummyTransportError())

        let result = await ClaudeOAuth.exchange(code: "c", state: "s", codeVerifier: "v", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a transport failure")
        case .failure(let error):
            XCTAssertEqual(error, .transport(endpoint: "token endpoint"))
        }
    }

    // MARK: - ClaudeOAuth.refresh

    func testClaudeRefreshKeepsOldRefreshTokenWhenServerOmitsANewOne() async {
        // Server response has no "refresh_token" key at all — the tolerant decoder
        // must not fail, and resolvedRefreshToken must fall back to the previous one.
        let body = Data(#"{"access_token":"new-access","expires_in":3600}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await ClaudeOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success(let response):
            XCTAssertNil(response.refreshToken)
            XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "old-refresh")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testClaudeRefreshUsesRotatedRefreshTokenWhenPresent() async {
        let body = Data(#"{"access_token":"new-access","refresh_token":"rotated-refresh"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await ClaudeOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success(let response):
            XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "rotated-refresh")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testClaudeRefreshFailsOnHTTPError() async {
        let transport = StubOAuthTransport(statusCode: 401, body: Data())

        let result = await ClaudeOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected failure on HTTP 401")
        case .failure(let error):
            XCTAssertEqual(error, .httpStatus(401, endpoint: "token endpoint"))
        }
    }

    // MARK: - CodexOAuth.exchange

    func testCodexExchangeSucceedsOn2xx() async {
        let body = Data(#"{"access_token":"a","refresh_token":"r","id_token":"j"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await CodexOAuth.exchange(code: "c", codeVerifier: "v", redirectPort: 1455, transport: transport)

        switch result {
        case .success(let response):
            XCTAssertEqual(response.accessToken, "a")
            XCTAssertEqual(response.refreshToken, "r")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testCodexExchangeFailsOnHTTPError() async {
        let transport = StubOAuthTransport(statusCode: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))

        let result = await CodexOAuth.exchange(code: "c", codeVerifier: "v", redirectPort: 1455, transport: transport)

        switch result {
        case .success:
            XCTFail("expected failure on HTTP 400")
        case .failure(let error):
            XCTAssertEqual(error, .httpStatus(400, endpoint: "token endpoint"))
        }
    }

    func testCodexExchangeFailsOnUnreadableBody() async {
        let transport = StubOAuthTransport(statusCode: 200, body: Data("not json at all".utf8))

        let result = await CodexOAuth.exchange(code: "c", codeVerifier: "v", redirectPort: 1455, transport: transport)

        switch result {
        case .success:
            XCTFail("expected a decoding failure on garbage body")
        case .failure(let error):
            XCTAssertEqual(error, .decodingFailed(endpoint: "token endpoint"))
        }
    }

    // MARK: - CodexOAuth.refresh — success paths

    func testCodexRefreshKeepsOldRefreshTokenWhenServerOmitsANewOne() async {
        let body = Data(#"{"access_token":"new-access"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success(let response):
            XCTAssertNil(response.refreshToken)
            XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "old-refresh")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testCodexRefreshUsesRotatedRefreshTokenWhenPresent() async {
        let body = Data(#"{"access_token":"new-access","refresh_token":"rotated-refresh"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 200, body: body)

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success(let response):
            XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "rotated-refresh")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    // MARK: - CodexOAuth.refresh — failure classification wired end to end

    func testCodexRefreshClassifiesExpiredAsPermanentThroughRefresh() async {
        let body = Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 400, body: body)

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a permanent refresh failure")
        case .failure(let error):
            XCTAssertEqual(error, .refreshPermanentlyFailed(.expired))
            XCTAssertTrue(error.isPermanentRefreshFailure)
        }
    }

    func testCodexRefreshClassifiesReusedAsPermanentThroughRefresh() async {
        let body = Data(#"{"error":"refresh_token_reused"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 400, body: body)

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a permanent refresh failure")
        case .failure(let error):
            XCTAssertEqual(error, .refreshPermanentlyFailed(.reused))
        }
    }

    func testCodexRefreshClassifiesInvalidatedAsPermanentThroughRefresh() async {
        let body = Data(#"{"code":"refresh_token_invalidated"}"#.utf8)
        let transport = StubOAuthTransport(statusCode: 400, body: body)

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a permanent refresh failure")
        case .failure(let error):
            XCTAssertEqual(error, .refreshPermanentlyFailed(.invalidated))
        }
    }

    func testCodexRefreshClassifiesBare401AsPermanentUnauthorizedThroughRefresh() async {
        let transport = StubOAuthTransport(statusCode: 401, body: Data())

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a permanent refresh failure")
        case .failure(let error):
            XCTAssertEqual(error, .refreshUnauthorized)
            XCTAssertTrue(error.isPermanentRefreshFailure)
        }
    }

    func testCodexRefreshClassifiesServerErrorAsTransientThroughRefresh() async {
        let transport = StubOAuthTransport(statusCode: 503, body: Data())

        let result = await CodexOAuth.refresh(refreshToken: "old-refresh", transport: transport)

        switch result {
        case .success:
            XCTFail("expected a transient refresh failure")
        case .failure(let error):
            XCTAssertEqual(error, .refreshTransientFailure(status: 503, endpoint: "token endpoint"))
            XCTAssertFalse(error.isPermanentRefreshFailure)
        }
    }
}
