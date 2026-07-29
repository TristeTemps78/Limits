import Foundation

/// Point d'entrée **unique** pour rafraîchir un token OAuth, partagé par l'app au
/// premier plan et la `BGAppRefreshTask`.
///
/// C'est la dette explicitement reportée de T2.2 en critère d'acceptation de T3.1
/// (cf. `TASKS.md`). Le problème qu'il résout : côté OpenAI, deux refresh **concurrents**
/// avec le même `refresh_token` produisent `refresh_token_reused`, qui est un échec
/// **définitif** — l'utilisateur devrait se reconnecter à cause d'une course interne à
/// l'app. Or l'app au premier plan et la tâche de fond peuvent parfaitement partir en
/// même temps (iOS réveille la tâche pendant que l'écran est allumé).
///
/// D'où le `SingleFlight` par provider, détenu ici et **nulle part ailleurs** : deux
/// appelants simultanés obtiennent le résultat du même unique appel réseau.
///
/// `shared` est le singleton à utiliser en production. Deux instances auraient chacune
/// son `SingleFlight` et ne coalesceraient rien — ce serait exactement le bug que ce type
/// existe pour empêcher, en plus difficile à voir. Les tests, eux, construisent leur
/// propre instance pour ne pas partager d'état.
public actor TokenRefreshCoordinator {
    public static let shared = TokenRefreshCoordinator()

    /// Résultat d'une tentative de rafraîchissement, du point de vue de l'appelant.
    public enum Outcome: Equatable, Sendable {
        /// Nouveau jeton utilisable (déjà persisté).
        case refreshed(StoredTokens)
        /// Échec **définitif** : seule une reconnexion aide. Ne jamais retenter.
        case needsReconnect
        /// Échec transitoire (réseau, 5xx…) : l'appelant applique son backoff.
        case transientFailure
    }

    private let claudeFlight = SingleFlight<Outcome>()
    private let codexFlight = SingleFlight<Outcome>()
    private let loadTokens: @Sendable (ProviderKind) -> StoredTokens?
    private let saveTokens: @Sendable (ProviderKind, StoredTokens) -> Bool

    /// Les accès au Keychain sont injectables pour que les tests n'y touchent jamais
    /// (un runner macOS headless n'a pas de trousseau déverrouillé fiable — même
    /// raisonnement que `SharedKeychainStoreTests`).
    public init(
        loadTokens: (@Sendable (ProviderKind) -> StoredTokens?)? = nil,
        saveTokens: (@Sendable (ProviderKind, StoredTokens) -> Bool)? = nil
    ) {
        self.loadTokens = loadTokens ?? { provider in
            let store = TokenStore(provider: provider == .claude ? .claude : .codex)
            guard case .success(let tokens) = store.load() else { return nil }
            return tokens
        }
        self.saveTokens = saveTokens ?? { provider, tokens in
            let store = TokenStore(provider: provider == .claude ? .claude : .codex)
            if case .success = store.save(tokens) { return true }
            return false
        }
    }

    /// Rafraîchit le token du provider en coalesçant les appels concurrents.
    public func refresh(
        provider: ProviderKind,
        transport: OAuthTransport = URLSession.shared
    ) async -> Outcome {
        let flight = provider == .claude ? claudeFlight : codexFlight
        let load = loadTokens
        let save = saveTokens
        do {
            return try await flight.run {
                await Self.performRefresh(provider: provider, transport: transport, loadTokens: load, saveTokens: save)
            }
        } catch {
            // `performRefresh` ne jette pas : ce chemin n'est atteint que si la tâche est
            // annulée. Transitoire — surtout pas « reconnecter », qui déconnecterait
            // l'utilisateur pour une annulation.
            return .transientFailure
        }
    }

    private static func performRefresh(
        provider: ProviderKind,
        transport: OAuthTransport,
        loadTokens: @Sendable (ProviderKind) -> StoredTokens?,
        saveTokens: @Sendable (ProviderKind, StoredTokens) -> Bool
    ) async -> Outcome {
        guard let existing = loadTokens(provider) else {
            // Aucun token stocké : il n'y a rien à rafraîchir, et retenter n'y changera rien.
            return .needsReconnect
        }

        switch provider {
        case .claude:
            switch await ClaudeOAuth.refresh(refreshToken: existing.refreshToken, transport: transport) {
            case .success(let response):
                let tokens = StoredTokens(
                    accessToken: response.accessToken,
                    // Rotation non systématique : conserver l'ancien si le serveur n'en
                    // renvoie pas (rapport de vérification, piège 2).
                    refreshToken: response.resolvedRefreshToken(previous: existing.refreshToken),
                    expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
                    accountID: existing.accountID
                )
                return saveTokens(provider, tokens) ? .refreshed(tokens) : .transientFailure
            case .failure(let error):
                return error.isPermanentAuthFailure ? .needsReconnect : .transientFailure
            }
        case .codex:
            switch await CodexOAuth.refresh(refreshToken: existing.refreshToken, transport: transport) {
            case .success(let response):
                guard let accessToken = response.accessToken else {
                    // 2xx sans `access_token` : anomalie serveur, pas une preuve que le
                    // refresh token est mort → transitoire.
                    return .transientFailure
                }
                let tokens = StoredTokens(
                    accessToken: accessToken,
                    refreshToken: response.resolvedRefreshToken(previous: existing.refreshToken),
                    expiresAt: nil,
                    // `account_id` n'est pas renvoyé au refresh : le perdre casserait
                    // l'en-tête `ChatGPT-Account-ID` des appels d'usage.
                    accountID: existing.accountID
                )
                return saveTokens(provider, tokens) ? .refreshed(tokens) : .transientFailure
            case .failure(let error):
                return error.isPermanentRefreshFailure ? .needsReconnect : .transientFailure
            }
        }
    }
}

extension ClaudeOAuthError {
    /// Vrai quand seule une reconnexion peut aider. Claude ne renvoie pas de codes
    /// d'erreur typés comme Codex : on s'appuie sur le statut HTTP de l'endpoint token,
    /// où 400/401/403 signifient que le `refresh_token` n'est plus accepté. Tout le reste
    /// (réseau, 5xx, réponse illisible) est transitoire — classer un 500 en
    /// « reconnecter » déconnecterait l'utilisateur pour une panne serveur passagère.
    public var isPermanentAuthFailure: Bool {
        switch self {
        case .httpStatus(let status, _):
            return status == 400 || status == 401 || status == 403
        case .invalidPastedCode, .stateMismatch:
            return true
        case .decodingFailed, .transport:
            return false
        }
    }
}
