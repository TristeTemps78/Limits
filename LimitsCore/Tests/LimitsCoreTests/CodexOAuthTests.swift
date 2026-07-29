import XCTest
@testable import LimitsCore

final class CodexOAuthTests: XCTestCase {
    // MARK: - Authorize URL

    func testAuthorizeURLHost() {
        let url = CodexOAuth.authorizeURL(codeChallenge: "challenge", state: "state123", redirectPort: 1455)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/oauth/authorize")
    }

    func testAuthorizeURLContainsAllExpectedQueryParameters() throws {
        let url = CodexOAuth.authorizeURL(codeChallenge: "the-challenge", state: "the-state", redirectPort: 1455)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(byName["redirect_uri"], "http://localhost:1455/auth/callback")
        XCTAssertEqual(byName["scope"], "openid profile email offline_access api.connectors.read api.connectors.invoke")
        XCTAssertEqual(byName["code_challenge"], "the-challenge")
        XCTAssertEqual(byName["code_challenge_method"], "S256")
        XCTAssertEqual(byName["id_token_add_organizations"], "true")
        XCTAssertEqual(byName["codex_cli_simplified_flow"], "true")
        XCTAssertEqual(byName["state"], "the-state")
        XCTAssertEqual(byName["originator"], "codex_cli_rs")
        XCTAssertNil(byName["prompt"], "no prompt parameter in the default flow — see verification report")
    }

    func testAuthorizeURLUsesFallbackPortInRedirectURI() throws {
        let url = CodexOAuth.authorizeURL(codeChallenge: "c", state: "s", redirectPort: 1457)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let redirect = items.first { $0.name == "redirect_uri" }?.value
        XCTAssertEqual(redirect, "http://localhost:1457/auth/callback")
    }

    // MARK: - State verification

    func testVerifyStateSucceedsOnMatch() {
        switch CodexOAuth.verifyState(received: "abc", expected: "abc") {
        case .success:
            break
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testVerifyStateFailsOnMismatch() {
        switch CodexOAuth.verifyState(received: "abc", expected: "xyz") {
        case .success:
            XCTFail("expected a stateMismatch failure")
        case .failure(let error):
            XCTAssertEqual(error, .stateMismatch)
        }
    }

    // MARK: - Exchange request (form-urlencoded — NOT JSON, unlike everything else)

    func testExchangeRequestIsFormURLEncodedNotJSON() throws {
        let request = CodexOAuth.makeExchangeRequest(code: "c0de", codeVerifier: "v3rifier", redirectPort: 1455)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://auth.openai.com/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        // Body must NOT be JSON-parseable as an object — it's a query string.
        XCTAssertNil(try? JSONSerialization.jsonObject(with: body))

        let pairs = bodyString.split(separator: "&").reduce(into: [String: String]()) { dict, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                dict[String(parts[0])] = String(parts[1]).removingPercentEncoding
            }
        }
        XCTAssertEqual(pairs["grant_type"], "authorization_code")
        XCTAssertEqual(pairs["code"], "c0de")
        XCTAssertEqual(pairs["redirect_uri"], "http://localhost:1455/auth/callback")
        XCTAssertEqual(pairs["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(pairs["code_verifier"], "v3rifier")
        // No "state" in this body, matching the verification report.
        XCTAssertNil(pairs["state"])
    }

    // MARK: - Refresh request (JSON — different from this provider's own exchange!)

    func testRefreshRequestIsJSONNotFormURLEncoded() throws {
        let request = CodexOAuth.makeRefreshRequest(refreshToken: "the-refresh-token")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://auth.openai.com/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "the-refresh-token")
    }

    // MARK: - Refresh token rotation

    func testResolvedRefreshTokenUsesNewTokenWhenPresent() {
        let response = CodexTokenResponse(accessToken: "a", refreshToken: "new-refresh", idToken: nil)
        XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "new-refresh")
    }

    func testResolvedRefreshTokenKeepsOldTokenWhenAbsent() {
        let response = CodexTokenResponse(accessToken: "a", refreshToken: nil, idToken: nil)
        XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "old-refresh")
    }

    // MARK: - Refresh failure classification

    func testClassifyRefreshTokenExpiredAsPermanentKnownReason() {
        let body = Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 400, body: body),
            .permanentKnownReason(.expired)
        )
    }

    func testClassifyRefreshTokenReusedAsPermanentKnownReason() {
        let body = Data(#"{"error":"refresh_token_reused"}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 400, body: body),
            .permanentKnownReason(.reused)
        )
    }

    func testClassifyRefreshTokenInvalidatedAsPermanentKnownReason() {
        let body = Data(#"{"error":{"code":"refresh_token_invalidated"}}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 400, body: body),
            .permanentKnownReason(.invalidated)
        )
    }

    /// `manager.rs::extract_refresh_token_error_code` also checks a bare `code` at
    /// the JSON root (no `error` wrapper) — re-verified against the upstream source
    /// during T2.2 review.
    func testClassifyRootLevelCodeWithNoErrorWrapperAsPermanentKnownReason() {
        let body = Data(#"{"code":"refresh_token_expired"}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 400, body: body),
            .permanentKnownReason(.expired)
        )
    }

    /// Upstream lowercases the extracted code (`to_ascii_lowercase`) before
    /// comparing — a differently-cased body must still classify correctly.
    func testClassifyIsCaseInsensitive() {
        let body = Data(#"{"error":{"code":"REFRESH_TOKEN_REUSED"}}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 400, body: body),
            .permanentKnownReason(.reused)
        )
    }

    /// The shape our own verification report originally (incorrectly) described —
    /// `error.error` — does not exist upstream and must NOT be treated as a known
    /// reason; it should fall through to the generic classification for its status.
    func testClassifyErrorDotErrorShapeIsNotRecognized() {
        let body = Data(#"{"error":{"error":"refresh_token_invalidated"}}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 429, body: body),
            .transient
        )
    }

    func testClassifyBare401WithUnparseableBodyAsPermanentUnauthorized() {
        let body = Data("not json".utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 401, body: body),
            .permanentUnauthorized
        )
    }

    func testClassifyServerErrorWithUnknownCodeAsTransient() {
        let body = Data(#"{"error":{"code":"rate_limited"}}"#.utf8)
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 429, body: body),
            .transient
        )
    }

    func testClassify5xxWithEmptyBodyAsTransient() {
        XCTAssertEqual(
            CodexRefreshFailureClassifier.classify(statusCode: 503, body: Data()),
            .transient
        )
    }

    func testCodexOAuthErrorIsPermanentRefreshFailureFlag() {
        XCTAssertTrue(CodexOAuthError.refreshPermanentlyFailed(.expired).isPermanentRefreshFailure)
        XCTAssertTrue(CodexOAuthError.refreshUnauthorized.isPermanentRefreshFailure)
        XCTAssertFalse(CodexOAuthError.refreshTransientFailure(status: 503, endpoint: "token endpoint").isPermanentRefreshFailure)
        XCTAssertFalse(CodexOAuthError.transport(endpoint: "token endpoint").isPermanentRefreshFailure)
    }
}
