import Foundation

/// OAuth endpoint/scope constants for both providers, verified against upstream
/// sources on 2026-07-29 — see `docs/oauth-verification-2026-07-29.md` for the full
/// derivation (installed `claude` CLI 2.1.220 binary strings for Claude, `openai/codex`
/// commit `cf7e9cfe` for Codex).
///
/// Deliberately **not** named `ProviderConfig.swift` / added to `ProviderConfig.swift`:
/// that file is owned by the T2.1 lot (usage-client config — anthropic-beta header,
/// User-Agent, polling values) landing in parallel on another branch. Keeping OAuth
/// constants in their own file avoids a same-file merge conflict between the two lots.
///
/// All values below are public OAuth client identifiers/endpoints (the same ones the
/// official `claude`/`codex` CLIs ship with) — not secrets (AGENTS.md rule 5).
public struct ClaudeOAuthConfig {
    public let clientID: String
    public let authorizeURL: URL
    public let redirectURI: String
    public let tokenURL: URL
    /// Scopes requested at login — 6 total, matching the standard interactive
    /// Pro/Max login flow (`loginWithClaudeAi = true`), not the Console/org flow.
    public let loginScopes: [String]
    /// Scopes sent with every refresh — 5, **without** `org:create_api_key`. This is
    /// not the same list as `loginScopes`; sending the login scopes on a refresh
    /// would diverge from what the official client does (see verification report,
    /// piège 8).
    public let refreshScopes: [String]

    public init(
        clientID: String,
        authorizeURL: URL,
        redirectURI: String,
        tokenURL: URL,
        loginScopes: [String],
        refreshScopes: [String]
    ) {
        self.clientID = clientID
        self.authorizeURL = authorizeURL
        self.redirectURI = redirectURI
        self.tokenURL = tokenURL
        self.loginScopes = loginScopes
        self.refreshScopes = refreshScopes
    }

    /// `URL(string:)!` below is applied only to compile-time literal strings owned by
    /// this file, never to network/user data — see AppGroup.swift-era discussion in
    /// T1.1 review for why that distinction matters; this is the safe case of it.
    public static let `default` = ClaudeOAuthConfig(
        clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        authorizeURL: URL(string: "https://claude.com/cai/oauth/authorize")!,
        redirectURI: "https://platform.claude.com/oauth/code/callback",
        tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        loginScopes: [
            "org:create_api_key",
            "user:profile",
            "user:inference",
            "user:sessions:claude_code",
            "user:mcp_servers",
            "user:file_upload"
        ],
        refreshScopes: [
            "user:profile",
            "user:inference",
            "user:sessions:claude_code",
            "user:mcp_servers",
            "user:file_upload"
        ]
    )
}

public struct CodexOAuthConfig {
    public let clientID: String
    public let authorizeURL: URL
    public let tokenURL: URL
    public let scopes: [String]
    public let originator: String
    /// `1455` is OpenAI's hard-coded default redirect port; `1457` is codex-rs's own
    /// fallback if `1455` is already taken (see verification report, piège 4).
    public let defaultPort: UInt16
    public let fallbackPort: UInt16

    public init(
        clientID: String,
        authorizeURL: URL,
        tokenURL: URL,
        scopes: [String],
        originator: String,
        defaultPort: UInt16,
        fallbackPort: UInt16
    ) {
        self.clientID = clientID
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.scopes = scopes
        self.originator = originator
        self.defaultPort = defaultPort
        self.fallbackPort = fallbackPort
    }

    public func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)/auth/callback"
    }

    /// Same note as `ClaudeOAuthConfig.default`: the two `URL(string:)!` below are
    /// compile-time literals we own, not runtime/network data — not the kind of
    /// force-unwrap that hides a real failure mode.
    public static let `default` = CodexOAuthConfig(
        clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        scopes: [
            "openid",
            "profile",
            "email",
            "offline_access",
            "api.connectors.read",
            "api.connectors.invoke"
        ],
        originator: "codex_cli_rs",
        defaultPort: 1455,
        fallbackPort: 1457
    )
}
