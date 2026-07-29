import Foundation

/// Le **seul** chemin de rafraîchissement d'usage, utilisé aussi bien par l'app au
/// premier plan que par la `BGAppRefreshTask`.
///
/// Il existe pour une raison précise : avant ce type, le premier plan rafraîchissait
/// lui-même les tokens en appelant `ClaudeOAuth.refresh`/`CodexOAuth.refresh`
/// directement. Ajouter un second appelant (la tâche de fond) aurait rendu possible ce
/// que `docs/oauth-verification-2026-07-29.md` (piège 3) décrit comme un échec
/// **définitif** : deux refresh concurrents avec le même `refresh_token` renvoient
/// `refresh_token_reused`, et l'utilisateur doit se reconnecter — à cause d'une course
/// interne à l'app. Ici tout passe par `TokenRefreshCoordinator`, donc par un
/// `SingleFlight` par provider.
///
/// Ce type ne décide **pas** s'il faut fetcher (c'est `PollingPolicy`/`AppRefreshGate`)
/// et n'écrit ni snapshot ni notification : il fait un aller-retour réseau et traduit le
/// résultat en `PollingOutcome`.
public struct UsageRefreshService {
    public struct Result_: Equatable, Sendable {
        public let outcome: PollingOutcome
        /// Non-`nil` seulement en cas de succès. Un échec ne doit **jamais** produire un
        /// snapshot vide qui écraserait les derniers chiffres connus (PLAN.md §6).
        public let snapshot: UsageSnapshot?

        public init(outcome: PollingOutcome, snapshot: UsageSnapshot?) {
            self.outcome = outcome
            self.snapshot = snapshot
        }
    }

    private let claudeClient: ClaudeUsageClient
    private let codexClient: CodexUsageClient
    private let coordinator: TokenRefreshCoordinator
    private let oauthTransport: OAuthTransport
    private let tokenLoader: @Sendable (ProviderKind) -> StoredTokens?

    public init(
        httpClient: HTTPClient,
        coordinator: TokenRefreshCoordinator = .shared,
        oauthTransport: OAuthTransport = URLSession.shared,
        tokenLoader: (@Sendable (ProviderKind) -> StoredTokens?)? = nil
    ) {
        self.oauthTransport = oauthTransport
        self.claudeClient = ClaudeUsageClient(httpClient: httpClient)
        self.codexClient = CodexUsageClient(httpClient: httpClient)
        self.coordinator = coordinator
        self.tokenLoader = tokenLoader ?? { provider in
            let store = TokenStore(provider: provider == .claude ? .claude : .codex)
            guard case .success(let tokens) = store.load() else { return nil }
            return tokens
        }
    }

    /// Fetch + une seule tentative de refresh sur 401.
    ///
    /// Une seule : si le token fraîchement rafraîchi se fait encore refuser, insister
    /// serait la boucle de retry sur le login qu'AGENTS.md interdit (§6.4 de PLAN.md).
    public func refresh(provider: ProviderKind) async -> Result_ {
        guard let tokens = tokenLoader(provider) else {
            // Aucun token : ce n'est pas une panne réseau, c'est une déconnexion.
            return Result_(outcome: .unauthorized, snapshot: nil)
        }

        // Codex sans `account_id` : l'en-tête `ChatGPT-Account-ID` est obligatoire, donc
        // l'appel échouerait. Il faut le détecter **ici**, avant tout appel réseau : sinon
        // le 401 qui en résulterait déclencherait une tentative de refresh, laquelle ne
        // renvoie jamais d'`account_id` (on conserve celui d'avant, donc toujours nul) —
        // on retenterait indéfiniment un appel structurellement voué à échouer. C'est un
        // état de connexion incomplète : seule une reconnexion le répare.
        if provider == .codex, tokens.accountID == nil {
            return Result_(outcome: .unauthorized, snapshot: nil)
        }

        switch await fetch(provider: provider, tokens: tokens) {
        case .success(let snapshot):
            return Result_(outcome: .success, snapshot: snapshot)
        case .failure(.unauthorized):
            return await refreshTokenThenRetryOnce(provider: provider)
        case .failure(.rateLimited(_, let retryAfter)):
            return Result_(outcome: .rateLimited(retryAfter: retryAfter), snapshot: nil)
        case .failure:
            return Result_(outcome: .otherFailure, snapshot: nil)
        }
    }

    private func refreshTokenThenRetryOnce(provider: ProviderKind) async -> Result_ {
        switch await coordinator.refresh(provider: provider, transport: oauthTransport) {
        case .needsReconnect:
            return Result_(outcome: .unauthorized, snapshot: nil)
        case .transientFailure:
            // Le refresh a échoué pour une raison passagère : surtout pas `.unauthorized`,
            // qui rendrait l'état « reconnecter » terminal pour une coupure réseau.
            return Result_(outcome: .otherFailure, snapshot: nil)
        case .refreshed(let tokens):
            switch await fetch(provider: provider, tokens: tokens) {
            case .success(let snapshot):
                return Result_(outcome: .success, snapshot: snapshot)
            case .failure(.rateLimited(_, let retryAfter)):
                return Result_(outcome: .rateLimited(retryAfter: retryAfter), snapshot: nil)
            case .failure(.unauthorized):
                // Token neuf, toujours 401 → il n'y a plus rien à tenter.
                return Result_(outcome: .unauthorized, snapshot: nil)
            case .failure:
                return Result_(outcome: .otherFailure, snapshot: nil)
            }
        }
    }

    private func fetch(
        provider: ProviderKind,
        tokens: StoredTokens
    ) async -> Swift.Result<UsageSnapshot, UsageClientError> {
        switch provider {
        case .claude:
            return await claudeClient.fetchUsage(accessToken: tokens.accessToken)
        case .codex:
            guard let accountID = tokens.accountID else {
                // L'en-tête `ChatGPT-Account-ID` est obligatoire : sans lui l'appel
                // échouerait de toute façon, et c'est un état de déconnexion, pas réseau.
                return .failure(.unauthorized(endpoint: "wham/usage"))
            }
            return await codexClient.fetchUsage(accessToken: tokens.accessToken, accountID: accountID)
        }
    }
}
