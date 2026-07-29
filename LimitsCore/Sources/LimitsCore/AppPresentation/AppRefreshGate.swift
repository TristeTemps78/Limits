import Foundation

/// Turns `PollingPolicy.canFetch`'s plain `Bool` into a reason the UI can actually
/// say out loud. T2.4's brief is explicit that a refused pull-to-refresh must tell
/// the user something, not silently do nothing — a spinner that snaps back with no
/// explanation reads as broken, not as "the app is protecting itself from a 429."
public enum AppRefreshGate {
    public enum Decision: Equatable, Sendable {
        case allowed
        /// Blocked purely by the minimum-interval rule (PollingPolicy's 15 min
        /// scheduled / 1 min manual), not by a failure.
        case tooSoon(retryAt: Date)
        /// Blocked by an active backoff window from a prior failure.
        case backoff(retryAt: Date)
        /// Blocked because the last token refresh failed permanently — refreshing
        /// won't help; reconnecting will.
        case needsReconnect
    }

    /// `policy` and `now` must share the same notion of "now" — in production both
    /// ultimately read `Date()` (the view model constructs `PollingPolicy()` with its
    /// default clock and calls this with `Date()`); in tests, inject the same fixed
    /// clock into both. This mirrors the existing convention elsewhere in the package
    /// (e.g. `ClaudeUsageClient`'s separately-injected `clock`) rather than
    /// introducing a new one.
    public static func evaluate(
        trigger: PollingTrigger,
        lastFetchAt: Date?,
        state: PollingState,
        policy: PollingPolicy,
        now: Date
    ) -> Decision {
        if policy.canFetch(trigger: trigger, lastFetchAt: lastFetchAt, state: state) {
            return .allowed
        }

        switch state {
        case .needsReconnect:
            return .needsReconnect
        case .backoff(let until, _):
            return .backoff(retryAt: until)
        case .idle:
            let minimumInterval = trigger == .scheduled
                ? PollingPolicy.minimumScheduledInterval
                : PollingPolicy.minimumManualInterval
            let retryAt = (lastFetchAt ?? now).addingTimeInterval(minimumInterval)
            return .tooSoon(retryAt: retryAt)
        }
    }
}
