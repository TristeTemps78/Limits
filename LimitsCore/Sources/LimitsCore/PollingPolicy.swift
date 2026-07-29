import Foundation

/// What triggered a fetch attempt — the two are throttled to different minimum
/// intervals (PLAN.md §6).
public enum PollingTrigger: Equatable, Sendable {
    case scheduled
    case manualRefresh
}

/// What happened on the last fetch attempt, as reported by the caller (the usage
/// clients' `UsageClientError`/success, translated by whoever drives the fetch loop —
/// not decided by `PollingPolicy` itself, which never touches the network).
public enum PollingOutcome: Equatable, Sendable {
    case success
    /// The caller already attempted an OAuth token refresh and it failed (or there
    /// was no refresh token to try). `PollingPolicy` does not perform the refresh
    /// itself — that's T2.2/T3.1's job — it only guarantees what happens *after*:
    /// no further automatic fetch attempts until something external (the user
    /// reconnecting) resets the state.
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case otherFailure
}

/// Current polling state — what a caller should show/do right now.
public enum PollingState: Equatable, Sendable {
    /// No backoff in effect; a fetch may proceed once the minimum interval for its
    /// trigger has elapsed.
    case idle
    /// Rate-limited or otherwise failing; don't fetch again before `until`.
    case backoff(until: Date, consecutiveFailures: Int)
    /// A 401 survived a token refresh attempt. Terminal until externally reset
    /// (`reset()`) by a successful reconnect — never re-entered automatically, which
    /// is what prevents the retry-loop-on-login AGENTS.md warns against.
    case needsReconnect
}

/// Network scheduling policy (PLAN.md §6, "anti-429"), as pure decision logic:
/// - Never fetch more often than every 15 min on a schedule, or more than once a
///   minute on a manual pull-to-refresh.
/// - On 429: respect `Retry-After` if present, else back off 30s → 2min → 10min →
///   30min.
/// - On 401: the caller tries a token refresh; if that also fails, stop retrying —
///   `.needsReconnect` is terminal until reset from outside.
/// - Conserving/exposing the last known snapshot on failure is **not** this type's
///   job: `SnapshotStore` is only ever overwritten on a successful fetch, so "last
///   good snapshot stays visible" falls out of that structurally, without
///   `PollingPolicy` needing to cache anything itself.
///
/// The clock is injected (never `Date()` read directly) so every rule above is
/// testable without waiting on a wall clock.
public struct PollingPolicy: Sendable {
    public static let minimumScheduledInterval: TimeInterval = 15 * 60
    public static let minimumManualInterval: TimeInterval = 60
    public static let backoffSteps: [TimeInterval] = [30, 120, 600, 1800]

    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    /// Whether a fetch is allowed right now.
    public func canFetch(trigger: PollingTrigger, lastFetchAt: Date?, state: PollingState) -> Bool {
        switch state {
        case .needsReconnect:
            return false
        case .backoff(let until, _):
            guard clock() >= until else { return false }
        case .idle:
            break
        }

        guard let lastFetchAt else { return true }
        let minimumInterval = trigger == .scheduled ? Self.minimumScheduledInterval : Self.minimumManualInterval
        return clock().timeIntervalSince(lastFetchAt) >= minimumInterval
    }

    /// Pure state transition: given the current state and what just happened, what's
    /// the next state?
    public func nextState(current: PollingState, outcome: PollingOutcome) -> PollingState {
        switch outcome {
        case .success:
            return .idle
        case .unauthorized:
            return .needsReconnect
        case .rateLimited(let retryAfter):
            let failures = Self.consecutiveFailures(in: current) + 1
            let delay = (retryAfter.map { $0 > 0 ? $0 : nil } ?? nil) ?? Self.backoffDelay(forFailureCount: failures)
            return .backoff(until: clock().addingTimeInterval(delay), consecutiveFailures: failures)
        case .otherFailure:
            let failures = Self.consecutiveFailures(in: current) + 1
            return .backoff(until: clock().addingTimeInterval(Self.backoffDelay(forFailureCount: failures)), consecutiveFailures: failures)
        }
    }

    /// External reset after the user successfully reconnects — the only way out of
    /// `.needsReconnect`.
    public func reset() -> PollingState {
        .idle
    }

    private static func consecutiveFailures(in state: PollingState) -> Int {
        if case .backoff(_, let failures) = state { return failures }
        return 0
    }

    private static func backoffDelay(forFailureCount failures: Int) -> TimeInterval {
        let index = min(max(failures - 1, 0), backoffSteps.count - 1)
        return backoffSteps[index]
    }
}
