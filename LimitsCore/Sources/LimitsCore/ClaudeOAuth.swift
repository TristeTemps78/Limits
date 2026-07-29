import Foundation

/// Claude OAuth (PKCE + manual "paste the code" flow — no local callback server;
/// Codex's local-server flow is separate, see `CodexOAuth.swift`/`LocalCallbackServer.swift`).
///
/// Endpoints/scopes verified 2026-07-29 against the installed `claude` CLI 2.1.220
/// binary — see `docs/oauth-verification-2026-07-29.md` §1-6. Both the token exchange
/// and the refresh are `application/json` (unlike Codex, whose initial exchange is
/// form-urlencoded — see `docs/oauth-verification-2026-07-29.md` piège 1). Do not
/// reuse this file's request builders for Codex or vice versa.
public enum ClaudeOAuth {
    /// Builds the authorize URL for the interactive Pro/Max login flow
    /// (`CLAUDE_AI_AUTHORIZE_URL` in the official client, i.e. `claude.com/cai/...`,
    /// **not** `claude.ai` — see verification report §3). `code=true` is sent by the
    /// official client on every variant of this flow and is replicated here even
    /// though its exact server-side effect isn't documented (report, "non vérifié").
    public static func authorizeURL(
        codeChallenge: String,
        state: String,
        config: ClaudeOAuthConfig = .default
    ) -> URL {
        var components = URLComponents()
        components.scheme = config.authorizeURL.scheme
        components.host = config.authorizeURL.host
        components.path = config.authorizeURL.path
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.loginScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        // `components.url` only returns nil for an inconsistent/incomplete
        // scheme+host+path, which can't happen here (all three come from our own
        // hardcoded, valid config). Falling back to the bare authorize URL (still
        // correct, just missing query items) is safer than force-unwrapping.
        return components.url ?? config.authorizeURL
    }

    // MARK: - Pasted code parsing

    public struct PastedCode: Equatable {
        public let code: String
        public let state: String
    }

    /// Splits the string the user pastes back into the app on the **first** `#`,
    /// matching the official client's own parsing (`re.split("#")`, first occurrence)
    /// — including its behavior of rejecting an empty code or empty state half with
    /// the same fixed, non-specific error. Extra `#` characters (if any) end up as
    /// part of `state`, exactly like the official client.
    ///
    /// Leading/trailing whitespace and newlines are trimmed from the whole pasted
    /// string **before** splitting — this is a paste from a web page, so a stray
    /// space or trailing newline around the copied text is the common case, not the
    /// rare one. Without this, a perfectly valid copy would fail `state` verification
    /// downstream with a `\n` silently embedded in it, and read to the user as "the
    /// app is broken" rather than "you copied whitespace."
    public static func parsePastedCode(_ pasted: String) -> Result<PastedCode, ClaudeOAuthError> {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else {
            return .failure(.invalidPastedCode)
        }
        let code = String(trimmed[trimmed.startIndex..<hashIndex])
        let state = String(trimmed[trimmed.index(after: hashIndex)...])
        guard !code.isEmpty, !state.isEmpty else {
            return .failure(.invalidPastedCode)
        }
        return .success(PastedCode(code: code, state: state))
    }

    // MARK: - State verification

    /// Verifies the `state` half of the pasted code matches the one this app
    /// generated for this login attempt (constant-time comparison — see
    /// `OAuthState`). A mismatch could mean the pasted value didn't originate from
    /// the redirect this app initiated; the failure never surfaces either value.
    public static func verifyState(received: String, expected: String) -> Result<Void, ClaudeOAuthError> {
        OAuthState.verify(received: received, expected: expected) ? .success(()) : .failure(.stateMismatch)
    }

    // MARK: - Request construction (pure — no network)

    public static func makeExchangeRequest(
        code: String,
        state: String,
        codeVerifier: String,
        config: ClaudeOAuthConfig = .default
    ) -> URLRequest {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": codeVerifier
        ]
        // A dictionary of plain strings is always valid JSON — `try?` here can only
        // ever produce `nil` on a genuine internal bug, not on any input we pass it.
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The refresh body's `scope` is **mandatory** and uses `config.refreshScopes`
    /// (5 entries, no `org:create_api_key`) — not `loginScopes`. See verification
    /// report §6.
    public static func makeRefreshRequest(
        refreshToken: String,
        config: ClaudeOAuthConfig = .default
    ) -> URLRequest {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "scope": config.refreshScopes.joined(separator: " ")
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Network calls

    public static func exchange(
        code: String,
        state: String,
        codeVerifier: String,
        config: ClaudeOAuthConfig = .default,
        transport: OAuthTransport = URLSession.shared
    ) async -> Result<ClaudeTokenResponse, ClaudeOAuthError> {
        let request = makeExchangeRequest(code: code, state: state, codeVerifier: codeVerifier, config: config)
        return await perform(request, endpoint: "token endpoint", transport: transport)
    }

    public static func refresh(
        refreshToken: String,
        config: ClaudeOAuthConfig = .default,
        transport: OAuthTransport = URLSession.shared
    ) async -> Result<ClaudeTokenResponse, ClaudeOAuthError> {
        let request = makeRefreshRequest(refreshToken: refreshToken, config: config)
        return await perform(request, endpoint: "token endpoint", transport: transport)
    }

    private static func perform(
        _ request: URLRequest,
        endpoint: String,
        transport: OAuthTransport
    ) async -> Result<ClaudeTokenResponse, ClaudeOAuthError> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return .failure(.transport(endpoint: endpoint))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.transport(endpoint: endpoint))
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.httpStatus(http.statusCode, endpoint: endpoint))
        }
        do {
            return .success(try JSONDecoder().decode(ClaudeTokenResponse.self, from: data))
        } catch {
            return .failure(.decodingFailed(endpoint: endpoint))
        }
    }
}

/// Response shape is treated tolerantly (AGENTS.md rule 3): only `access_token` is
/// required, everything else is optional, unknown fields are ignored.
public struct ClaudeTokenResponse: Decodable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let refreshTokenExpiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
    }

    public init(accessToken: String, refreshToken: String?, expiresIn: Int?, refreshTokenExpiresIn: Int?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
    }

    /// The refresh token to persist after this response: the new one if the server
    /// rotated it, otherwise the one we had before the call — rotation is not
    /// systematic (verification report, piège 2). Overwriting with `nil` when the
    /// server simply didn't send a new one would silently sign the user out.
    public func resolvedRefreshToken(previous: String) -> String {
        refreshToken ?? previous
    }
}

public enum ClaudeOAuthError: Error, LocalizedError, Equatable {
    /// Mirrors the official client's own fixed message — never carries the actual
    /// pasted text (AGENTS.md rule 5/6: no code/state/token in an error message).
    case invalidPastedCode
    case stateMismatch
    case httpStatus(Int, endpoint: String)
    case decodingFailed(endpoint: String)
    case transport(endpoint: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPastedCode:
            return "Code invalide. Vérifiez que le code complet a bien été copié."
        case .stateMismatch:
            return "La connexion a échoué (state invalide) — merci de recommencer."
        case .httpStatus(let status, let endpoint):
            return "Erreur HTTP \(status) sur \(endpoint)."
        case .decodingFailed(let endpoint):
            return "Réponse illisible depuis \(endpoint)."
        case .transport(let endpoint):
            return "Erreur réseau vers \(endpoint)."
        }
    }
}
