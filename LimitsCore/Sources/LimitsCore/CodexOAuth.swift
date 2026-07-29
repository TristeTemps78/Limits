import Foundation

/// Codex OAuth (PKCE + local callback server on :1455/:1457 — see
/// `App/LocalCallbackServer.swift`).
///
/// Endpoints/scopes verified 2026-07-29 against `openai/codex` commit `cf7e9cfe` —
/// see `docs/oauth-verification-2026-07-29.md` §7. **The initial code exchange is
/// `application/x-www-form-urlencoded`; the refresh is `application/json`** — these
/// are genuinely different from each other, and both different from Claude's
/// (always-JSON) shape. Do not reuse this file's request builders for Claude or vice
/// versa, and do not "fix" the exchange/refresh asymmetry within this file — it's
/// correct, not an inconsistency (verification report, piège 1).
public enum CodexOAuth {
    /// Builds the full authorize URL including the two parameters PLAN.md hadn't
    /// documented (`id_token_add_organizations`, `codex_cli_simplified_flow`) and the
    /// wider scope than originally assumed (verification report §7).
    public static func authorizeURL(
        codeChallenge: String,
        state: String,
        redirectPort: UInt16,
        config: CodexOAuthConfig = .default
    ) -> URL {
        var components = URLComponents()
        components.scheme = config.authorizeURL.scheme
        components.host = config.authorizeURL.host
        components.path = config.authorizeURL.path
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI(port: redirectPort)),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: config.originator)
        ]
        // Same reasoning as ClaudeOAuth.authorizeURL: this can't actually return nil
        // given our own hardcoded, valid config, but a fallback is safer than `!`.
        return components.url ?? config.authorizeURL
    }

    // MARK: - State verification

    /// Same purpose and same constant-time comparison as `ClaudeOAuth.verifyState`
    /// (see `OAuthState`) — verifies the `state` the local callback server received
    /// matches the one generated for this login attempt.
    public static func verifyState(received: String, expected: String) -> Result<Void, CodexOAuthError> {
        OAuthState.verify(received: received, expected: expected) ? .success(()) : .failure(.stateMismatch)
    }

    // MARK: - Request construction (pure — no network)

    public static func makeExchangeRequest(
        code: String,
        codeVerifier: String,
        redirectPort: UInt16,
        config: CodexOAuthConfig = .default
    ) -> URLRequest {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", config.redirectURI(port: redirectPort)),
            ("client_id", config.clientID),
            ("code_verifier", codeVerifier)
        ]
        request.httpBody = Data(formURLEncode(params).utf8)
        return request
    }

    public static func makeRefreshRequest(
        refreshToken: String,
        config: CodexOAuthConfig = .default
    ) -> URLRequest {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        // A dictionary of plain strings is always valid JSON — `try?` here can only
        // ever produce `nil` on a genuine internal bug, not on any input we pass it.
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func formURLEncode(_ params: [(String, String)]) -> String {
        params.map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }.joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Network calls

    public static func exchange(
        code: String,
        codeVerifier: String,
        redirectPort: UInt16,
        config: CodexOAuthConfig = .default,
        transport: OAuthTransport = URLSession.shared
    ) async -> Result<CodexTokenResponse, CodexOAuthError> {
        let request = makeExchangeRequest(code: code, codeVerifier: codeVerifier, redirectPort: redirectPort, config: config)
        return await send(request, endpoint: "token endpoint", transport: transport)
    }

    /// Unlike `exchange`, a non-2xx response here is run through
    /// `CodexRefreshFailureClassifier` to distinguish a permanent failure (reconnect
    /// required, never retry) from a transient one (retry with backoff) — see
    /// verification report, piège 3.
    public static func refresh(
        refreshToken: String,
        config: CodexOAuthConfig = .default,
        transport: OAuthTransport = URLSession.shared
    ) async -> Result<CodexTokenResponse, CodexOAuthError> {
        let request = makeRefreshRequest(refreshToken: refreshToken, config: config)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            return .failure(.transport(endpoint: "token endpoint"))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.transport(endpoint: "token endpoint"))
        }
        guard (200..<300).contains(http.statusCode) else {
            switch CodexRefreshFailureClassifier.classify(statusCode: http.statusCode, body: data) {
            case .permanentKnownReason(let reason):
                return .failure(.refreshPermanentlyFailed(reason))
            case .permanentUnauthorized:
                return .failure(.refreshUnauthorized)
            case .transient:
                return .failure(.refreshTransientFailure(status: http.statusCode, endpoint: "token endpoint"))
            }
        }
        return decode(data, endpoint: "token endpoint")
    }

    private static func send(
        _ request: URLRequest,
        endpoint: String,
        transport: OAuthTransport
    ) async -> Result<CodexTokenResponse, CodexOAuthError> {
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
        return decode(data, endpoint: endpoint)
    }

    private static func decode(_ data: Data, endpoint: String) -> Result<CodexTokenResponse, CodexOAuthError> {
        do {
            return .success(try JSONDecoder().decode(CodexTokenResponse.self, from: data))
        } catch {
            return .failure(.decodingFailed(endpoint: endpoint))
        }
    }
}

/// All three fields are optional in the response (verification report, piège 2):
/// notably `refresh_token` is not always present on a refresh (rotation isn't
/// systematic).
public struct CodexTokenResponse: Decodable, Equatable {
    public let accessToken: String?
    public let refreshToken: String?
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }

    public init(accessToken: String?, refreshToken: String?, idToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
    }

    /// The refresh token to persist after this response: the new one if present,
    /// otherwise whatever we had before — never overwrite with `nil` just because
    /// this particular response didn't include a fresh one.
    public func resolvedRefreshToken(previous: String) -> String {
        refreshToken ?? previous
    }
}

// MARK: - Refresh failure classification

/// The three codes `codex-rs/login/src/auth/manager.rs::classify_refresh_token_failure`
/// treats as **definitive** — never retry, surface a "reconnect" state.
public enum CodexRefreshFailureReason: String, Equatable {
    case expired = "refresh_token_expired"
    case reused = "refresh_token_reused"
    case invalidated = "refresh_token_invalidated"
}

public enum RefreshFailureKind: Equatable {
    /// One of the three known, definitive error codes.
    case permanentKnownReason(CodexRefreshFailureReason)
    /// A bare 401 with no parseable/known error code — still treated as definitive,
    /// per the verification report ("un statut 401 générique ... = échec permanent").
    case permanentUnauthorized
    /// Anything else: network hiccup, 5xx, rate limit, ... — safe to retry with
    /// backoff (PollingPolicy).
    case transient
}

public enum CodexRefreshFailureClassifier {
    /// Matches `codex-rs/login/src/auth/manager.rs::extract_refresh_token_error_code`
    /// (l. 1407-1431, commit `cf7e9cfe`) exactly, re-verified line-by-line against
    /// that source during T2.2 review — **not** the shape our own verification
    /// report originally described (it mentioned an `error.error` path that doesn't
    /// exist upstream; that report has since been corrected). In order:
    /// 1. `error.code` (nested object) — the primary shape.
    /// 2. `error` itself, if it's a bare string.
    /// 3. `code` at the JSON **root** (no `error` wrapper at all).
    /// The extracted code is lowercased before comparison
    /// (`to_ascii_lowercase` upstream) — a body like `"REFRESH_TOKEN_REUSED"` must
    /// still classify as permanent.
    public static func classify(statusCode: Int, body: Data) -> RefreshFailureKind {
        if let code = errorCode(fromBody: body), let reason = CodexRefreshFailureReason(rawValue: code.lowercased()) {
            return .permanentKnownReason(reason)
        }
        if statusCode == 401 {
            return .permanentUnauthorized
        }
        return .transient
    }

    private static func errorCode(fromBody body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] {
            if let nested = error as? [String: Any], let code = nested["code"] as? String {
                return code
            }
            if let code = error as? String {
                return code
            }
        }
        if let code = json["code"] as? String {
            return code
        }
        return nil
    }
}

public enum CodexOAuthError: Error, LocalizedError, Equatable {
    case stateMismatch
    case httpStatus(Int, endpoint: String)
    case decodingFailed(endpoint: String)
    case transport(endpoint: String)
    case refreshPermanentlyFailed(CodexRefreshFailureReason)
    case refreshUnauthorized
    case refreshTransientFailure(status: Int, endpoint: String)

    /// Whether the caller should show "reconnect" and stop retrying, rather than
    /// schedule a retry with backoff (verification report, piège 3).
    public var isPermanentRefreshFailure: Bool {
        switch self {
        case .refreshPermanentlyFailed, .refreshUnauthorized:
            return true
        case .stateMismatch, .httpStatus, .decodingFailed, .transport, .refreshTransientFailure:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .stateMismatch:
            return "La connexion a échoué (state invalide) — merci de recommencer."
        case .httpStatus(let status, let endpoint):
            return "Erreur HTTP \(status) sur \(endpoint)."
        case .decodingFailed(let endpoint):
            return "Réponse illisible depuis \(endpoint)."
        case .transport(let endpoint):
            return "Erreur réseau vers \(endpoint)."
        case .refreshPermanentlyFailed(let reason):
            return "Session expirée (\(reason.rawValue)) — reconnexion nécessaire."
        case .refreshUnauthorized:
            return "Session expirée — reconnexion nécessaire."
        case .refreshTransientFailure(let status, let endpoint):
            return "Échec temporaire (HTTP \(status)) sur \(endpoint) — nouvelle tentative prévue."
        }
    }
}
