import Foundation

/// Last known OAuth/connection status for one provider, as reported by whoever last
/// wrote `SharedUsageSnapshots` (the app, on the main thread or in a `BGAppRefreshTask`
/// — see T3.1). Stored per-provider in `SharedUsageSnapshots` because it can disagree
/// with whether a snapshot exists: a provider can be `.needsReconnect` while still
/// carrying its last successful `UsageSnapshot`, which is exactly the "last known
/// numbers stay visible, with a reconnect banner on top" behavior PLAN.md §6 asks for.
///
/// Nothing writes this field yet — T2.3 only *reads* it to decide what a widget shows,
/// ahead of T3.1 wiring it up from `PollingPolicy.PollingState`. See
/// `SharedUsageSnapshots.claudeStatus`/`codexStatus` for the decode-compatibility note.
public enum ProviderConnectionStatus: String, Codable, Equatable, Sendable {
    /// Never logged in for this provider.
    case notConnected
    /// Last fetch attempt succeeded, or hasn't failed hard enough to require
    /// reconnecting (transient/backoff failures stay `.connected` — that's the whole
    /// point of `PollingPolicy`'s backoff state, it's not `.needsReconnect`).
    case connected
    /// Mirrors `PollingPolicy.PollingState.needsReconnect`: a 401 survived a token
    /// refresh attempt. Terminal until the user reconnects — a widget must never imply
    /// this will resolve itself.
    case needsReconnect
}
