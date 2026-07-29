import Foundation

/// Coalesces concurrent calls into a single in-flight operation.
///
/// Intended use: serializing OAuth token refreshes so the app-foreground path and a
/// background refresh task can never both hit the refresh endpoint at once — that's
/// exactly what triggers Codex's `refresh_token_reused` failure (see
/// `docs/oauth-verification-2026-07-29.md`, piège 3). Keep **one `SingleFlight`
/// instance per provider/token**, owned by whichever layer orchestrates refreshes
/// (e.g. a future `RefreshManager` — out of this lot's scope, see AGENTS.md/TASKS.md
/// for T2.x). `ClaudeOAuth.refresh`/`CodexOAuth.refresh` themselves stay stateless
/// static functions on purpose; wrap calls to them with a shared `SingleFlight`
/// instance at the orchestration layer rather than here.
public actor SingleFlight<Value: Sendable> {
    private var inFlight: Task<Value, Error>?

    public init() {}

    /// If a call is already in flight, awaits and returns *its* result instead of
    /// starting a second one — every concurrent caller gets the same outcome from the
    /// same single underlying attempt.
    public func run(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
