import Foundation
import LimitsCore

/// Orchestrates fetching both providers' usage, applying `PollingPolicy` (anti-429,
/// AGENTS.md rule 7), refreshing tokens on 401, and persisting the shared snapshot to
/// the App Group container for the widgets.
///
/// State (`PollingState`, last snapshot, last outcome) is kept in memory only for
/// this v1 — it resets on relaunch, which is acceptable per PLAN.md §4 ("l'ouverture
/// de l'app force aussi un fetch"). Background refresh (`BGAppRefreshTask`,
/// `RefreshManager.swift` in PLAN.md §4) and the single-flight coordination between
/// foreground and background refreshes (`SingleFlight`, T2.2) are **not** built here
/// — this view model only ever runs in the foreground, so there is no concurrent
/// refresh to serialize yet. See the T2.4 report for what that leaves for a later lot.
@MainActor
final class DashboardViewModel: ObservableObject {
    struct ProviderRuntime {
        var pollingState: PollingState = .idle
        var lastOutcome: PollingOutcome?
        var lastFetchAt: Date?
        var lastSnapshot: UsageSnapshot?
    }

    @Published private(set) var claudeConnected = false
    @Published private(set) var codexConnected = false
    @Published private(set) var claudeRuntime = ProviderRuntime()
    @Published private(set) var codexRuntime = ProviderRuntime()
    @Published private(set) var lastSnapshotWriteSucceeded = true
    @Published var refreshNotice: String?

    private let policy = PollingPolicy()
    private let claudeTokenStore = TokenStore(provider: .claude)
    private let codexTokenStore = TokenStore(provider: .codex)
    private let claudeUsageClient = ClaudeUsageClient(httpClient: URLSessionHTTPClient())
    private let codexUsageClient = CodexUsageClient(httpClient: URLSessionHTTPClient())
    private let snapshotStore = SnapshotStore(
        containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    )

    /// Re-checks stored tokens (cheap Keychain reads) — call on appear and after any
    /// connect/disconnect action, not on every render.
    func refreshConnectionStatus() {
        if case .success = claudeTokenStore.load() {
            claudeConnected = true
        } else {
            claudeConnected = false
        }
        if case .success = codexTokenStore.load() {
            codexConnected = true
        } else {
            codexConnected = false
        }
    }

    /// Sequential, not concurrent — both calls are already throttled by
    /// `PollingPolicy`/`AppRefreshGate`, and a pull-to-refresh gesture doesn't need
    /// the two providers to race each other. Keeping this simple beats shaving a
    /// few hundred milliseconds off a manual refresh.
    func fetchAllIfNeeded(trigger: PollingTrigger) async {
        await fetchClaude(trigger: trigger)
        await fetchCodex(trigger: trigger)
    }

    // MARK: - Claude

    func fetchClaude(trigger: PollingTrigger) async {
        guard claudeConnected else { return }

        let decision = AppRefreshGate.evaluate(
            trigger: trigger,
            lastFetchAt: claudeRuntime.lastFetchAt,
            state: claudeRuntime.pollingState,
            policy: policy,
            now: Date()
        )
        guard decision == .allowed else {
            if trigger == .manualRefresh {
                refreshNotice = Self.noticeText(for: decision)
            }
            return
        }

        guard case .success(let tokens) = claudeTokenStore.load() else {
            claudeConnected = false
            return
        }

        let outcome = await performClaudeFetch(tokens: tokens)
        claudeRuntime.lastFetchAt = Date()
        claudeRuntime.lastOutcome = outcome
        claudeRuntime.pollingState = policy.nextState(current: claudeRuntime.pollingState, outcome: outcome)
        persistSnapshot()
    }

    private func performClaudeFetch(tokens: StoredTokens) async -> PollingOutcome {
        switch await claudeUsageClient.fetchUsage(accessToken: tokens.accessToken) {
        case .success(let snapshot):
            claudeRuntime.lastSnapshot = snapshot
            return .success
        case .failure(.unauthorized):
            return await refreshClaudeThenRetry(tokens: tokens)
        case .failure(.rateLimited(_, let retryAfter)):
            return .rateLimited(retryAfter: retryAfter)
        case .failure:
            return .otherFailure
        }
    }

    private func refreshClaudeThenRetry(tokens: StoredTokens) async -> PollingOutcome {
        switch await ClaudeOAuth.refresh(refreshToken: tokens.refreshToken) {
        case .success(let response):
            let newRefreshToken = response.resolvedRefreshToken(previous: tokens.refreshToken)
            let newTokens = StoredTokens(
                accessToken: response.accessToken,
                refreshToken: newRefreshToken,
                expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            )
            _ = claudeTokenStore.save(newTokens)

            switch await claudeUsageClient.fetchUsage(accessToken: response.accessToken) {
            case .success(let snapshot):
                claudeRuntime.lastSnapshot = snapshot
                return .success
            case .failure(.rateLimited(_, let retryAfter)):
                return .rateLimited(retryAfter: retryAfter)
            case .failure:
                return .otherFailure
            }
        case .failure(let error):
            // ClaudeOAuthError doesn't carry an explicit "permanent vs transient"
            // flag the way CodexOAuthError does (T2.2 didn't need one — Claude's
            // refresh failure modes weren't verified in as much depth as Codex's
            // three named error codes, see docs/oauth-verification-2026-07-29.md).
            // Judgment call: treat any *HTTP* failure (the server actively rejected
            // the refresh) as permanent, and anything transport-level (no response
            // at all — offline, timeout) as transient. A false "transient" here just
            // means one more retry before `.needsReconnect`, which is the safe
            // direction to be wrong in.
            switch error {
            case .transport:
                return .otherFailure
            case .httpStatus, .decodingFailed, .invalidPastedCode, .stateMismatch:
                return .unauthorized
            }
        }
    }

    // MARK: - Codex

    func fetchCodex(trigger: PollingTrigger) async {
        guard codexConnected else { return }

        let decision = AppRefreshGate.evaluate(
            trigger: trigger,
            lastFetchAt: codexRuntime.lastFetchAt,
            state: codexRuntime.pollingState,
            policy: policy,
            now: Date()
        )
        guard decision == .allowed else {
            if trigger == .manualRefresh {
                refreshNotice = Self.noticeText(for: decision)
            }
            return
        }

        guard case .success(let tokens) = codexTokenStore.load(), let accountID = tokens.accountID else {
            codexConnected = false
            return
        }

        let outcome = await performCodexFetch(tokens: tokens, accountID: accountID)
        codexRuntime.lastFetchAt = Date()
        codexRuntime.lastOutcome = outcome
        codexRuntime.pollingState = policy.nextState(current: codexRuntime.pollingState, outcome: outcome)
        persistSnapshot()
    }

    private func performCodexFetch(tokens: StoredTokens, accountID: String) async -> PollingOutcome {
        switch await codexUsageClient.fetchUsage(accessToken: tokens.accessToken, accountID: accountID) {
        case .success(let snapshot):
            codexRuntime.lastSnapshot = snapshot
            return .success
        case .failure(.unauthorized):
            return await refreshCodexThenRetry(tokens: tokens, accountID: accountID)
        case .failure(.rateLimited(_, let retryAfter)):
            return .rateLimited(retryAfter: retryAfter)
        case .failure:
            return .otherFailure
        }
    }

    private func refreshCodexThenRetry(tokens: StoredTokens, accountID: String) async -> PollingOutcome {
        switch await CodexOAuth.refresh(refreshToken: tokens.refreshToken) {
        case .success(let response):
            guard let newAccessToken = response.accessToken else {
                // A 2xx refresh response with no access_token is a malformed-response
                // situation, not a confirmed "reconnect required" — treat as
                // transient rather than forcing the user to reconnect for what might
                // be a transient server-side glitch.
                return .otherFailure
            }
            let newRefreshToken = response.resolvedRefreshToken(previous: tokens.refreshToken)
            let newTokens = StoredTokens(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
                expiresAt: nil,
                accountID: accountID
            )
            _ = codexTokenStore.save(newTokens)

            switch await codexUsageClient.fetchUsage(accessToken: newAccessToken, accountID: accountID) {
            case .success(let snapshot):
                codexRuntime.lastSnapshot = snapshot
                return .success
            case .failure(.rateLimited(_, let retryAfter)):
                return .rateLimited(retryAfter: retryAfter)
            case .failure:
                return .otherFailure
            }
        case .failure(let error):
            // Unlike Claude, Codex's refresh failures ARE classified with real
            // confidence (verification report + T2.2 review, re-checked against
            // codex-rs source line by line) — trust `isPermanentRefreshFailure`
            // directly rather than guessing.
            return error.isPermanentRefreshFailure ? .unauthorized : .otherFailure
        }
    }

    // MARK: - Shared

    private func persistSnapshot() {
        let snapshots = SharedUsageSnapshots(
            updatedAt: Date(),
            claude: claudeRuntime.lastSnapshot,
            codex: codexRuntime.lastSnapshot
        )
        switch snapshotStore.write(snapshots) {
        case .success:
            lastSnapshotWriteSucceeded = true
        case .failure:
            lastSnapshotWriteSucceeded = false
        }
    }

    static func noticeText(for decision: AppRefreshGate.Decision) -> String? {
        switch decision {
        case .allowed:
            return nil
        case .tooSoon(let retryAt):
            let seconds = max(1, Int(retryAt.timeIntervalSinceNow))
            return "Merci de patienter encore \(seconds) s avant de rafraîchir à nouveau."
        case .backoff(let retryAt):
            let seconds = max(1, Int(retryAt.timeIntervalSinceNow))
            return "Le serveur a demandé de ralentir — nouvelle tentative dans \(seconds) s."
        case .needsReconnect:
            return "Reconnecte ce compte avant de rafraîchir (voir Réglages)."
        }
    }
}
