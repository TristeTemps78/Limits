import XCTest
@testable import LimitsCore

final class ClaudeOAuthTests: XCTestCase {
    // MARK: - Pasted code parsing

    func testParsePastedCodeNominalCase() throws {
        let result = ClaudeOAuth.parsePastedCode("abc123#the-state-value")
        switch result {
        case .success(let parsed):
            XCTAssertEqual(parsed.code, "abc123")
            XCTAssertEqual(parsed.state, "the-state-value")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testParsePastedCodeFailsWhenHashIsAbsent() {
        let result = ClaudeOAuth.parsePastedCode("abc123nostatehere")
        XCTAssertEqual(result, .failure(.invalidPastedCode))
    }

    func testParsePastedCodeFailsWhenCodeHalfIsEmpty() {
        let result = ClaudeOAuth.parsePastedCode("#the-state-value")
        XCTAssertEqual(result, .failure(.invalidPastedCode))
    }

    func testParsePastedCodeFailsWhenStateHalfIsEmpty() {
        let result = ClaudeOAuth.parsePastedCode("abc123#")
        XCTAssertEqual(result, .failure(.invalidPastedCode))
    }

    func testParsePastedCodeSplitsOnFirstHashOnly() throws {
        // Extra "#" characters end up in `state`, matching the official client's own
        // first-occurrence split.
        let result = ClaudeOAuth.parsePastedCode("abc123#state#with#extra#hashes")
        switch result {
        case .success(let parsed):
            XCTAssertEqual(parsed.code, "abc123")
            XCTAssertEqual(parsed.state, "state#with#extra#hashes")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testParsePastedCodeFailsOnEmptyString() {
        XCTAssertEqual(ClaudeOAuth.parsePastedCode(""), .failure(.invalidPastedCode))
    }

    // MARK: - Authorize URL

    func testAuthorizeURLUsesClaudeComCaiHost() {
        let url = ClaudeOAuth.authorizeURL(codeChallenge: "challenge", state: "state123")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "claude.com")
        XCTAssertEqual(url.path, "/cai/oauth/authorize")
    }

    func testAuthorizeURLContainsAllExpectedQueryParameters() throws {
        let url = ClaudeOAuth.authorizeURL(codeChallenge: "the-challenge", state: "the-state")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(byName["code"], "true")
        XCTAssertEqual(byName["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["redirect_uri"], "https://platform.claude.com/oauth/code/callback")
        XCTAssertEqual(
            byName["scope"],
            "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
        )
        XCTAssertEqual(byName["code_challenge"], "the-challenge")
        XCTAssertEqual(byName["code_challenge_method"], "S256")
        XCTAssertEqual(byName["state"], "the-state")
    }

    // MARK: - State verification

    func testVerifyStateSucceedsOnMatch() {
        switch ClaudeOAuth.verifyState(received: "abc", expected: "abc") {
        case .success:
            break
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testVerifyStateFailsOnMismatch() {
        switch ClaudeOAuth.verifyState(received: "abc", expected: "xyz") {
        case .success:
            XCTFail("expected a stateMismatch failure")
        case .failure(let error):
            XCTAssertEqual(error, .stateMismatch)
        }
    }

    // MARK: - Exchange request

    func testExchangeRequestIsJSONPost() throws {
        let request = ClaudeOAuth.makeExchangeRequest(code: "c0de", state: "st4te", codeVerifier: "v3rifier")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://platform.claude.com/v1/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["grant_type"], "authorization_code")
        XCTAssertEqual(json["code"], "c0de")
        XCTAssertEqual(json["state"], "st4te")
        XCTAssertEqual(json["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(json["redirect_uri"], "https://platform.claude.com/oauth/code/callback")
        XCTAssertEqual(json["code_verifier"], "v3rifier")
    }

    // MARK: - Refresh request

    func testRefreshRequestIsJSONPostWithRefreshScopeNotLoginScope() throws {
        let request = ClaudeOAuth.makeRefreshRequest(refreshToken: "the-refresh-token")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, URL(string: "https://platform.claude.com/v1/oauth/token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "the-refresh-token")
        XCTAssertEqual(json["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        // 5 scopes, no org:create_api_key — deliberately different from the login scope.
        XCTAssertEqual(
            json["scope"],
            "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
        )
        XCTAssertFalse((json["scope"] ?? "").contains("org:create_api_key"))
    }

    // MARK: - Refresh token rotation

    func testResolvedRefreshTokenUsesNewTokenWhenPresent() {
        let response = ClaudeTokenResponse(accessToken: "a", refreshToken: "new-refresh", expiresIn: 3600, refreshTokenExpiresIn: nil)
        XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "new-refresh")
    }

    func testResolvedRefreshTokenKeepsOldTokenWhenAbsent() {
        let response = ClaudeTokenResponse(accessToken: "a", refreshToken: nil, expiresIn: 3600, refreshTokenExpiresIn: nil)
        XCTAssertEqual(response.resolvedRefreshToken(previous: "old-refresh"), "old-refresh")
    }

    // MARK: - Response decoding is tolerant

    func testTokenResponseDecodesWithOnlyAccessTokenPresent() throws {
        let json = #"{"access_token":"a","unexpected_new_field":123}"#
        let response = try JSONDecoder().decode(ClaudeTokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "a")
        XCTAssertNil(response.refreshToken)
    }
}
