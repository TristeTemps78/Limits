import Foundation

/// `code`/`state` extracted from the local OAuth callback request received by
/// `App/LocalCallbackServer.swift` (Codex only — Claude uses the manual paste flow,
/// see `ClaudeOAuth.PastedCode`).
public struct OAuthCallback: Equatable {
    public let code: String
    public let state: String

    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

/// Parses the raw first line of an HTTP GET request
/// (`GET /auth/callback?code=...&state=... HTTP/1.1`) into `code`/`state`. Kept in
/// LimitsCore rather than in `App/LocalCallbackServer.swift` so it's covered by
/// `swift test` — the socket plumbing around it needs `NWListener` and can't run in
/// CI, but this parsing has zero networking dependency (rule 4, AGENTS.md).
public enum CodexCallbackParser {
    public static func parse(requestLine raw: String) -> OAuthCallback? {
        guard let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        let target = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(target)") else {
            return nil
        }
        let items = components.queryItems ?? []
        guard
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
            let state = items.first(where: { $0.name == "state" })?.value, !state.isEmpty
        else {
            return nil
        }
        return OAuthCallback(code: code, state: state)
    }
}
