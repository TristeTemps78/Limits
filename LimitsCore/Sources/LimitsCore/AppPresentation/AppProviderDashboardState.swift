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
///
/// Freshness display is deliberately **not** carried here as a precomputed value:
/// each case that has a snapshot exposes it, and the view derives "à jour il y a X"
/// from `SnapshotFreshness.relativeLabel(fetchedAt: snapshot.fetchedAt, now:)` at
/// render time (see `DashboardView`'s `TimelineView`) — reusing the same freshness
/// vocabulary the widget uses (T2.3), rather than this type baking in a second,
/// independently-computed age.
public enum AppProviderDashboardState: Equatable, Sendable {
    /// No tokens stored for this provider — the two providers are independent
    /// (PLAN.md §1), each renders this state on its own.
    case notConnected
    /// Connected, but no fetch has ever completed successfully yet.
    case loading
    /// A snapshot is available and there is nothing wrong to report.
    case content(snapshot: UsageSnapshot)
    /// A snapshot is available but the polling loop is currently backing off
    /// (network error or 429) — the old data is still shown, with why it might be
    /// stale and when the next attempt will happen.
    case staleContent(snapshot: UsageSnapshot, reason: AppStaleReason, retryAt: Date)
    /// No snapshot has ever been fetched, and the loop is currently backing off.
    /// Distinct from `.loading`: `.loading` implies data is imminent, this doesn't.
    case blockedNoData(reason: AppStaleReason, retryAt: Date)
    /// A token refresh failed permanently (`PollingState.needsReconnect`) — show a
    /// reconnect banner. The last snapshot (if any) stays visible underneath rather
    /// than being hidden, since it's still the most recent real data the user has.
    case needsReconnect(lastSnapshot: UsageSnapshot?)
}

/// Pure reducer: given what's known about one provider right now, decide what state
/// its dashboard section is in. No I/O, no clock — unlike `SnapshotFreshness`'s own
/// `now`-dependent formatting, this reduction only needs the *shape* of the current
/// polling state, not the current time.
public enum AppProviderDashboardStateBuilder {
    public static func build(
        isConnected: Bool,
        lastSnapshot: UsageSnapshot?,
        pollingState: PollingState,
        lastOutcome: PollingOutcome?
    ) -> AppProviderDashboardState {
        guard isConnected else { return .notConnected }

        switch pollingState {
        case .needsReconnect:
            return .needsReconnect(lastSnapshot: lastSnapshot)

        case .backoff(let until, _):
            let reason = staleReason(from: lastOutcome)
            if let snapshot = lastSnapshot {
                return .staleContent(snapshot: snapshot, reason: reason, retryAt: until)
            }
            return .blockedNoData(reason: reason, retryAt: until)

        case .idle:
            guard let snapshot = lastSnapshot else { return .loading }
            return .content(snapshot: snapshot)
        }
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
