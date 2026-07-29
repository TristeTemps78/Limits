import Foundation

/// État de rafraîchissement **persistant**, partagé entre l'app au premier plan et la
/// `BGAppRefreshTask`.
///
/// Pourquoi il ne peut pas rester en mémoire : une tâche de fond est réveillée par iOS
/// dans un processus qui peut avoir été relancé, avec un `DashboardViewModel` tout neuf.
/// Sans persistance, chaque réveil repartirait avec `lastFetchAt == nil` et `state ==
/// .idle`, donc :
/// - le minimum de 15 minutes entre deux fetchs (règle 7 d'AGENTS.md, anti-429) serait
///   contourné à chaque réveil ;
/// - un backoff en cours après un 429 serait **oublié**, et on retaperait sur un
///   endpoint qui vient justement de nous demander de ralentir ;
/// - le journal des notifications (`NotificationLedger`) serait vide, donc le même seuil
///   de 80 % re-notifierait à chaque réveil.
///
/// Stocké dans les `UserDefaults` du groupe d'app plutôt que dans un fichier : ce sont
/// des métadonnées minuscules, et l'écriture doit rester atomique et bon marché même si
/// iOS suspend le processus juste après. Aucun token n'y transite — uniquement des dates
/// et des compteurs (règle 5).
public struct RefreshStateStore {
    /// Vue persistable de `PollingState` (qui porte des valeurs associées et n'est pas
    /// `Codable`). Traduction explicite plutôt que conformance ajoutée à l'enum : le
    /// format sur disque ne doit pas suivre silencieusement un refactor de l'enum.
    struct PersistedProviderState: Codable, Equatable {
        var lastFetchAt: Date?
        var backoffUntil: Date?
        var consecutiveFailures: Int
        var needsReconnect: Bool

        init(lastFetchAt: Date?, state: PollingState) {
            self.lastFetchAt = lastFetchAt
            switch state {
            case .idle:
                backoffUntil = nil
                consecutiveFailures = 0
                needsReconnect = false
            case .backoff(let until, let failures):
                backoffUntil = until
                consecutiveFailures = failures
                needsReconnect = false
            case .needsReconnect:
                backoffUntil = nil
                consecutiveFailures = 0
                needsReconnect = true
            }
        }

        var pollingState: PollingState {
            if needsReconnect { return .needsReconnect }
            if let backoffUntil { return .backoff(until: backoffUntil, consecutiveFailures: consecutiveFailures) }
            return .idle
        }
    }

    struct Persisted: Codable, Equatable {
        var claude: PersistedProviderState?
        var codex: PersistedProviderState?
        var ledger: NotificationLedger

        init(claude: PersistedProviderState? = nil, codex: PersistedProviderState? = nil, ledger: NotificationLedger = NotificationLedger()) {
            self.claude = claude
            self.codex = codex
            self.ledger = ledger
        }
    }

    private static let key = "refresh-state.v1"
    private let defaults: UserDefaults?

    /// `defaults` injectable : en production les `UserDefaults` du groupe d'app, en test
    /// une suite jetable. `nil` (groupe indisponible) est un état toléré — on dégrade en
    /// « pas de mémoire » plutôt que de planter.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public init(appGroupIdentifier: String = AppGroup.identifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Lecture

    public func lastFetchAt(for provider: ProviderKind) -> Date? {
        state(for: provider)?.lastFetchAt
    }

    public func pollingState(for provider: ProviderKind) -> PollingState {
        state(for: provider)?.pollingState ?? .idle
    }

    public func notificationLedger() -> NotificationLedger {
        load().ledger
    }

    // MARK: - Écriture

    public func record(provider: ProviderKind, lastFetchAt: Date, state: PollingState) {
        var persisted = load()
        let entry = PersistedProviderState(lastFetchAt: lastFetchAt, state: state)
        switch provider {
        case .claude: persisted.claude = entry
        case .codex: persisted.codex = entry
        }
        save(persisted)
    }

    public func save(ledger: NotificationLedger) {
        var persisted = load()
        persisted.ledger = ledger
        save(persisted)
    }

    /// Remet un provider à zéro après une reconnexion réussie : sans ça, l'état
    /// `.needsReconnect` étant terminal, l'app resterait bloquée même avec un token neuf.
    public func clear(provider: ProviderKind) {
        var persisted = load()
        switch provider {
        case .claude: persisted.claude = nil
        case .codex: persisted.codex = nil
        }
        save(persisted)
    }

    // MARK: - Interne

    private func state(for provider: ProviderKind) -> PersistedProviderState? {
        let persisted = load()
        return provider == .claude ? persisted.claude : persisted.codex
    }

    func load() -> Persisted {
        guard
            let data = defaults?.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            // Format illisible (ancienne version, écriture interrompue) : on repart d'un
            // état vide plutôt que de propager une erreur. Le coût d'un état perdu est un
            // fetch de trop, pas une donnée fausse.
            return Persisted()
        }
        return decoded
    }

    private func save(_ persisted: Persisted) {
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
