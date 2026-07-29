import Foundation
import LimitsCore

/// Orchestrates fetching both providers' usage, applying `PollingPolicy` (anti-429,
/// AGENTS.md rule 7), refreshing tokens on 401, and persisting the shared snapshot to
/// the App Group container for the widgets.
///
/// **T3.1** — ce view model ne fait plus lui-même les appels réseau ni les refresh de
/// token : tout passe par `LimitsCore.UsageRefreshService`, exactement comme la
/// `BGAppRefreshTask` (`RefreshManager`). Deux raisons, toutes deux structurantes :
///
/// 1. **La course sur le refresh de token.** Deux refresh concurrents avec le même
///    `refresh_token` renvoient `refresh_token_reused` côté OpenAI, un échec *définitif*
///    (cf. `docs/oauth-verification-2026-07-29.md`, piège 3). L'app au premier plan et la
///    tâche de fond peuvent parfaitement partir en même temps — iOS réveille la tâche
///    pendant que l'écran est allumé. Passer par le `TokenRefreshCoordinator` (donc par un
///    `SingleFlight` par provider) est la seule façon de l'empêcher.
/// 2. **La mémoire du backoff.** `PollingState` et `lastFetchAt` sont désormais persistés
///    dans `RefreshStateStore` : sans ça, relancer l'app remettrait le compteur à zéro et
///    contournerait le minimum de 15 minutes comme un backoff en cours après un 429.
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
    @Published private(set) var lastSnapshotError: SnapshotStoreError?
    @Published var refreshNotice: String?

    private let policy = PollingPolicy()
    private let claudeTokenStore = TokenStore(provider: .claude)
    private let codexTokenStore = TokenStore(provider: .codex)
    private let service = UsageRefreshService(httpClient: URLSessionHTTPClient())
    private let stateStore = RefreshStateStore()
    private let snapshotStore = SnapshotStore(
        containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    )
    /// Seuils de notification, injectés depuis les réglages. Le premier plan programme les
    /// mêmes notifications que la tâche de fond : un franchissement constaté pendant que
    /// l'utilisateur regarde l'écran doit l'alerter comme un autre.
    var notificationThresholds: [Double] = NotificationPlanner.defaultThresholds

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
        // L'état persistant fait autorité sur le backoff et le « reconnecter » : le
        // recharger ici évite qu'un simple relancement de l'app contourne un backoff en
        // cours (règle 7 d'AGENTS.md, anti-429).
        claudeRuntime.pollingState = stateStore.pollingState(for: .claude)
        claudeRuntime.lastFetchAt = stateStore.lastFetchAt(for: .claude)
        codexRuntime.pollingState = stateStore.pollingState(for: .codex)
        codexRuntime.lastFetchAt = stateStore.lastFetchAt(for: .codex)
    }

    /// Sequential, not concurrent — both calls are already throttled by
    /// `PollingPolicy`/`AppRefreshGate`, and a pull-to-refresh gesture doesn't need
    /// the two providers to race each other. Keeping this simple beats shaving a
    /// few hundred milliseconds off a manual refresh.
    func fetchAllIfNeeded(trigger: PollingTrigger) async {
        await fetchClaude(trigger: trigger)
        await fetchCodex(trigger: trigger)
    }

    // MARK: - Fetch (un seul chemin, partagé avec la tâche de fond)

    func fetchClaude(trigger: PollingTrigger) async {
        await fetch(provider: .claude, trigger: trigger)
    }

    func fetchCodex(trigger: PollingTrigger) async {
        await fetch(provider: .codex, trigger: trigger)
    }

    private func fetch(provider: ProviderKind, trigger: PollingTrigger) async {
        guard isConnected(provider) else { return }

        var runtime = self.runtime(for: provider)
        let decision = AppRefreshGate.evaluate(
            trigger: trigger,
            lastFetchAt: runtime.lastFetchAt,
            state: runtime.pollingState,
            policy: policy,
            now: Date()
        )
        guard decision == .allowed else {
            // Un rafraîchissement manuel refusé doit le dire : un pull-to-refresh qui ne
            // fait rien en silence passe pour une app cassée.
            if trigger == .manualRefresh {
                refreshNotice = Self.noticeText(for: decision)
            }
            return
        }

        let result = await service.refresh(provider: provider)
        let now = Date()
        runtime.lastFetchAt = now
        runtime.lastOutcome = result.outcome
        runtime.pollingState = policy.nextState(current: runtime.pollingState, outcome: result.outcome)
        // Un échec ne remplace jamais le dernier snapshot connu (PLAN.md §6.3) : on
        // n'écrase que sur succès.
        if let snapshot = result.snapshot {
            runtime.lastSnapshot = snapshot
        }
        setRuntime(runtime, for: provider)
        stateStore.record(provider: provider, lastFetchAt: now, state: runtime.pollingState)

        persistSnapshot()
        await scheduleNotifications()
    }

    private func isConnected(_ provider: ProviderKind) -> Bool {
        provider == .claude ? claudeConnected : codexConnected
    }

    private func runtime(for provider: ProviderKind) -> ProviderRuntime {
        provider == .claude ? claudeRuntime : codexRuntime
    }

    private func setRuntime(_ runtime: ProviderRuntime, for provider: ProviderKind) {
        switch provider {
        case .claude: claudeRuntime = runtime
        case .codex: codexRuntime = runtime
        }
    }

    /// Le premier plan programme les mêmes notifications que la tâche de fond, avec le
    /// **même journal persistant** : c'est lui qui garantit qu'un seuil déjà annoncé ne
    /// re-notifie pas, quel que soit le chemin qui a constaté le franchissement.
    private func scheduleNotifications() async {
        let snapshots = currentSharedSnapshots()
        let plan = NotificationPlanner.plan(
            snapshots: snapshots,
            thresholds: notificationThresholds,
            ledger: stateStore.notificationLedger(),
            now: Date()
        )
        await LocalNotificationScheduler.apply(plan.notifications)
        stateStore.save(ledger: plan.ledger)
    }

    // MARK: - Shared

    private func currentSharedSnapshots() -> SharedUsageSnapshots {
        SharedUsageSnapshots(
            updatedAt: Date(),
            claude: claudeRuntime.lastSnapshot,
            codex: codexRuntime.lastSnapshot,
            claudeStatus: connectionStatus(isConnected: claudeConnected, pollingState: claudeRuntime.pollingState),
            codexStatus: connectionStatus(isConnected: codexConnected, pollingState: codexRuntime.pollingState)
        )
    }

    private func persistSnapshot() {
        let snapshots = currentSharedSnapshots()
        switch snapshotStore.write(snapshots) {
        case .success:
            lastSnapshotWriteSucceeded = true
            lastSnapshotError = nil
        case .failure(let error):
            lastSnapshotWriteSucceeded = false
            lastSnapshotError = error
        }
    }

    /// `ProviderConnectionStatus.swift`'s doc comment notes this field is written by
    /// "T3.1's background-refresh loop" — but the foreground path already has every
    /// piece of information needed to report it accurately, so it's wired up here
    /// too rather than left `nil` until a later lot. T3.1 only needs to add the same
    /// mapping on the background-fetch path; nothing here should need to change for
    /// that to slot in cleanly.
    private func connectionStatus(isConnected: Bool, pollingState: PollingState) -> ProviderConnectionStatus {
        guard isConnected else { return .notConnected }
        if case .needsReconnect = pollingState { return .needsReconnect }
        return .connected
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
