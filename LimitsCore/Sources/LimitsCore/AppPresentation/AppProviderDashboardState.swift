import Foundation

/// Why a provider's dashboard content might be stale (or, with no snapshot yet at
/// all, why there's nothing to show).
public enum AppStaleReason: Equatable, Sendable {
    case rateLimited
    case networkError
}

/// What one provider's section of the dashboard should show right now — the state
/// machine T2.4's brief calls out as the actual point of this lot (loading / empty /
/// error / reconnect), reduced to exactly the cases the view needs to switch on.
/// Every case that can show a number also carries the freshness age needed for
/// `AppFreshnessFormatter`, computed once here rather than re-derived in the view.
public enum AppProviderDashboardState: Equatable, Sendable {
    /// No tokens stored for this provider — the two providers are independent
    /// (PLAN.md §1), each renders this state on its own.
    case notConnected
    /// Connected, but no fetch has ever completed successfully yet.
    case loading
    /// A snapshot is available and there is nothing wrong to report.
    case content(snapshot: UsageSnapshot, freshnessSeconds: Int)
    /// A snapshot is available but the polling loop is currently backing off
    /// (network error or 429) — the old data is still shown, with why it might be
    /// stale and when the next attempt will happen.
    case staleContent(snapshot: UsageSnapshot, freshnessSeconds: Int, reason: AppStaleReason, retryAt: Date)
    /// No snapshot has ever been fetched, and the loop is currently backing off.
    /// Distinct from `.loading`: `.loading` implies data is imminent, this doesn't.
    case blockedNoData(reason: AppStaleReason, retryAt: Date)
    /// A token refresh failed permanently (`PollingState.needsReconnect`) — show a
    /// reconnect banner. The last snapshot (if any) stays visible underneath rather
    /// than being hidden, since it's still the most recent real data the user has.
    case needsReconnect(lastSnapshot: UsageSnapshot?, freshnessSeconds: Int?)
}

/// Pure reducer: given what's known about one provider right now, decide what state
/// its dashboard section is in. No I/O, no clock read internally — `now` is always
/// injected, matching every other testable type in this package.
public enum AppProviderDashboardStateBuilder {
    public static func build(
        isConnected: Bool,
        lastSnapshot: UsageSnapshot?,
        pollingState: PollingState,
        lastOutcome: PollingOutcome?,
        now: Date
    ) -> AppProviderDashboardState {
        guard isConnected else { return .notConnected }

        switch pollingState {
        case .needsReconnect:
            return .needsReconnect(
                lastSnapshot: lastSnapshot,
                freshnessSeconds: lastSnapshot.map { freshnessSeconds(of: $0, now: now) }
            )

        case .backoff(let until, _):
            let reason = staleReason(from: lastOutcome)
            if let snapshot = lastSnapshot {
                return .staleContent(
                    snapshot: snapshot,
                    freshnessSeconds: freshnessSeconds(of: snapshot, now: now),
                    reason: reason,
                    retryAt: until
                )
            }
            return .blockedNoData(reason: reason, retryAt: until)

        case .idle:
            guard let snapshot = lastSnapshot else { return .loading }
            return .content(snapshot: snapshot, freshnessSeconds: freshnessSeconds(of: snapshot, now: now))
        }
    }

    private static func freshnessSeconds(of snapshot: UsageSnapshot, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(snapshot.fetchedAt)))
    }

    /// `PollingOutcome` only distinguishes `.rateLimited` from everything else that
    /// isn't success/unauthorized (see `PollingPolicy.swift`'s own doc comment) — the
    /// `.unauthorized`/`.success`/`nil` branches below are defensive fallbacks for
    /// combinations that shouldn't occur alongside `.backoff` in practice (a
    /// `.needsReconnect`-producing or successful outcome shouldn't leave the state
    /// machine in `.backoff`), not expected inputs.
    private static func staleReason(from outcome: PollingOutcome?) -> AppStaleReason {
        switch outcome {
        case .rateLimited:
            return .rateLimited
        case .otherFailure, .unauthorized, .success, .none:
            return .networkError
        }
    }
}
