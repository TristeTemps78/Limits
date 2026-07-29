import Foundation

/// Failure surfaced by `ClaudeUsageClient`/`CodexUsageClient`. Every case carries only
/// the endpoint (a fixed string like `"api/oauth/usage"`) and, where meaningful, an
/// HTTP status or a `Retry-After` value — never the response body, headers, or the
/// token that was sent. Rule 6 of AGENTS.md: an error logs the status and the
/// endpoint, nothing else.
public enum UsageClientError: Error, Equatable, Sendable {
    case transport(endpoint: String, reason: String)
    case decoding(endpoint: String)
    case unauthorized(endpoint: String)
    case rateLimited(endpoint: String, retryAfter: TimeInterval?)
    case httpStatus(endpoint: String, status: Int)
}
