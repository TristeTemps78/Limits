import Foundation
import WidgetKit
import LimitsCore

/// Le fil complet décrit par PLAN.md §4, côté arrière-plan :
/// fetch → snapshot App Group → notifications locales → rechargement des timelines.
///
/// Volontairement **sans état en mémoire** : une `BGAppRefreshTask` est réveillée par iOS
/// dans un processus qui peut avoir été relancé entre-temps. Tout ce qui doit survivre
/// (dernier fetch, backoff en cours, journal des seuils notifiés) vit dans
/// `RefreshStateStore`, et les données d'usage dans `SnapshotStore`. C'est ce qui garantit
/// qu'un réveil ne contourne pas le minimum de 15 minutes ni un backoff après 429
/// (règle 7 d'AGENTS.md).
struct RefreshManager {
    private let policy = PollingPolicy()
    private let stateStore = RefreshStateStore()
    private let snapshotStore = SnapshotStore(
        containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    )
    private let service = UsageRefreshService(httpClient: URLSessionHTTPClient())
    private let thresholds: [Double]

    init(thresholds: [Double] = NotificationPlanner.defaultThresholds) {
        self.thresholds = thresholds
    }

    /// Rafraîchit les deux providers, puis met à jour snapshot, notifications et widgets.
    /// Retourne `true` si au moins un provider a été rafraîchi avec succès (utile pour
    /// renseigner honnêtement `setTaskCompleted(success:)`).
    @discardableResult
    func runScheduledRefresh() async -> Bool {
        var anySuccess = false

        // On repart du snapshot déjà sur disque : un provider dont le fetch échoue doit
        // conserver ses derniers chiffres, et surtout ne pas être effacé parce que
        // *l'autre* provider a réussi (PLAN.md §6.3).
        var claudeSnapshot = existingSnapshots?.claude
        var codexSnapshot = existingSnapshots?.codex
        var statuses: [ProviderKind: ProviderConnectionStatus] = [:]

        for provider in ProviderKind.allCases {
            // Un provider jamais connecté doit rester `.notConnected` : le faire passer par
            // le fetch le ferait échouer en `.unauthorized`, donc basculer en
            // « reconnecter » — un état qui inviterait l'utilisateur à reconnecter un
            // compte qu'il n'a jamais lié.
            guard Self.hasStoredTokens(for: provider) else {
                statuses[provider] = .notConnected
                continue
            }

            let currentState = stateStore.pollingState(for: provider)
            let lastFetchAt = stateStore.lastFetchAt(for: provider)

            guard policy.canFetch(trigger: .scheduled, lastFetchAt: lastFetchAt, state: currentState) else {
                statuses[provider] = status(for: currentState)
                continue
            }

            let result = await service.refresh(provider: provider)
            let newState = policy.nextState(current: currentState, outcome: result.outcome)
            stateStore.record(provider: provider, lastFetchAt: Date(), state: newState)
            statuses[provider] = status(for: newState)

            if let snapshot = result.snapshot {
                anySuccess = true
                switch provider {
                case .claude: claudeSnapshot = snapshot
                case .codex: codexSnapshot = snapshot
                }
            }
        }

        let snapshots = SharedUsageSnapshots(
            updatedAt: Date(),
            claude: claudeSnapshot,
            codex: codexSnapshot,
            claudeStatus: statuses[.claude],
            codexStatus: statuses[.codex]
        )
        _ = snapshotStore.write(snapshots)

        await scheduleNotifications(for: snapshots)

        // Le widget ne fait aucun réseau (règle 8) : sans ce rechargement il continuerait
        // d'afficher l'ancien snapshot jusqu'à sa propre échéance de timeline.
        WidgetCenter.shared.reloadAllTimelines()

        return anySuccess
    }

    private var existingSnapshots: SharedUsageSnapshots? {
        if case .success(let snapshots) = snapshotStore.read() { return snapshots }
        return nil
    }

    private func scheduleNotifications(for snapshots: SharedUsageSnapshots) async {
        let plan = NotificationPlanner.plan(
            snapshots: snapshots,
            thresholds: thresholds,
            ledger: stateStore.notificationLedger(),
            now: Date()
        )
        await LocalNotificationScheduler.apply(plan.notifications)
        // Persister le journal est obligatoire : sans ça le même seuil de 80 %
        // re-notifierait à chaque réveil de la tâche de fond.
        stateStore.save(ledger: plan.ledger)
    }

    private func status(for state: PollingState) -> ProviderConnectionStatus {
        if case .needsReconnect = state { return .needsReconnect }
        return .connected
    }

    static func hasStoredTokens(for provider: ProviderKind) -> Bool {
        let store = TokenStore(provider: provider == .claude ? .claude : .codex)
        if case .success = store.load() { return true }
        return false
    }
}
