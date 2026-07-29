import Foundation

/// Minimal seam for sending an already-built `URLRequest` and getting back
/// `(Data, URLResponse)` — just enough to substitute a fake in tests.
///
/// This does **not** decide `Content-Type`, HTTP method, or body: those are fully
/// owned by each provider's own `make*Request` functions (see
/// `ClaudeOAuth.swift`/`CodexOAuth.swift`), precisely so this shared seam can't
/// accidentally blur Claude's JSON-everywhere shape with Codex's mixed
/// form-urlencoded/JSON shape — see docs/oauth-verification-2026-07-29.md, piège 1.
public protocol OAuthTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OAuthTransport {
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
