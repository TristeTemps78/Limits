import Foundation
import AuthenticationServices
import LimitsCore

/// Drives Codex's OAuth flow: start the local callback server, open the authorize
/// page once the server actually reports which port it bound to (`:1455` or the
/// `:1457` fallback — see `LocalCallbackServer.start`'s doc comment for why the
/// browser must not open before that), capture the redirect, exchange, extract
/// `account_id` from the `id_token`.
@MainActor
final class CodexConnectViewModel: NSObject, ObservableObject {
    @Published private(set) var state: AppOnboardingConnectionState = .notConnected

    private var pendingVerifier: String?
    private var expectedState: String?
    /// The port the local server actually bound to for this attempt — `:1455` or the
    /// `:1457` fallback. The token exchange's `redirect_uri` must match the one used
    /// in the authorize request bit for bit, so this has to be threaded through to
    /// `exchange(code:verifier:)` rather than assumed to always be the default port.
    private var boundPort: UInt16?
    private let localServer = LocalCallbackServer()
    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationContext = WebAuthPresentationContext()
    private let tokenStore = TokenStore(provider: .codex)

    override init() {
        super.init()
        loadExistingConnection()
    }

    func loadExistingConnection() {
        if case .success = tokenStore.load() {
            state = .connected
        }
    }

    func startLogin() {
        guard state.canStartNewAttempt else { return }

        let pair = PKCE.generate()
        let generatedState = OAuthState.generate()
        pendingVerifier = pair.verifier
        expectedState = generatedState
        state = .connecting

        localServer.start(
            ports: [CodexOAuthConfig.default.defaultPort, CodexOAuthConfig.default.fallbackPort],
            onBound: { [weak self] port in
                Task { @MainActor in
                    self?.openBrowser(port: port, codeChallenge: pair.challenge, state: generatedState)
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    self?.handleCallback(result)
                }
            }
        )
    }

    private func openBrowser(port: UInt16, codeChallenge: String, state generatedState: String) {
        // The user may have already cancelled between starting the server and it
        // reporting ready — don't pop a browser sheet for an attempt nobody wants
        // anymore.
        guard case .connecting = state else { return }
        boundPort = port

        let url = CodexOAuth.authorizeURL(codeChallenge: codeChallenge, state: generatedState, redirectPort: port)
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            // The local server (not this callback) is what actually captures the
            // redirect — this only fires on user cancellation or a session-level
            // error before that happens.
            guard let self, error != nil, case .connecting = self.state else { return }
            self.cancel()
        }
        session.presentationContextProvider = presentationContext
        webAuthSession = session
        session.start()
    }

    /// Must be called whenever the user backs out before the callback completes —
    /// otherwise the loopback listener stays open and the *next* attempt fails on
    /// "port already in use" with a message that won't make sense to whoever sees it
    /// (flagged explicitly in the T2.2 review).
    func cancel() {
        localServer.stop()
        webAuthSession?.cancel()
        webAuthSession = nil
        pendingVerifier = nil
        expectedState = nil
        boundPort = nil
        if case .connecting = state {
            state = .notConnected
        }
    }

    private func handleCallback(_ result: Result<OAuthCallback, LocalCallbackServer.ServerError>) {
        switch result {
        case .failure:
            webAuthSession?.cancel()
            webAuthSession = nil
            state = .failed(message: "Impossible de recevoir la réponse de connexion (port local indisponible). Réessaie.")
        case .success(let callback):
            webAuthSession?.cancel()
            webAuthSession = nil
            guard let verifier = pendingVerifier, let expectedState else {
                state = .failed(message: "Connexion expirée — relance depuis le bouton « Se connecter ».")
                return
            }
            switch CodexOAuth.verifyState(received: callback.state, expected: expectedState) {
            case .failure:
                state = .failed(message: "La connexion a expiré ou a été altérée — relance depuis le bouton « Se connecter ».")
            case .success:
                state = .exchangingToken
                Task { await exchange(code: callback.code, verifier: verifier) }
            }
        }
    }

    private func exchange(code: String, verifier: String) async {
        let redirectPort = boundPort ?? CodexOAuthConfig.default.defaultPort
        let result = await CodexOAuth.exchange(code: code, codeVerifier: verifier, redirectPort: redirectPort)
        switch result {
        case .success(let response):
            guard
                let accessToken = response.accessToken,
                let refreshToken = response.refreshToken,
                let idToken = response.idToken
            else {
                state = .failed(message: "Réponse de connexion incomplète. Réessaie.")
                return
            }
            guard case .success(let accountID) = CodexIDToken.accountID(fromIDToken: idToken) else {
                state = .failed(message: "Impossible d'identifier le compte ChatGPT dans la réponse. Réessaie.")
                return
            }
            let tokens = StoredTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: nil, accountID: accountID)
            guard case .success = tokenStore.save(tokens) else {
                state = .failed(message: "Connexion réussie mais impossible d'enregistrer les identifiants sur cet appareil.")
                return
            }
            pendingVerifier = nil
            expectedState = nil
            boundPort = nil
            // `PollingState.needsReconnect` est terminal : sans ce reset, une reconnexion
            // reussie laisserait l'app bloquee malgre un token neuf.
            RefreshStateStore().clear(provider: .codex)
            state = .connected
            NotificationCenter.default.post(name: .limitsProviderConnectionChanged, object: nil)
        case .failure:
            state = .failed(message: "Échec de la connexion. Vérifie ta connexion réseau et réessaie.")
        }
    }

    func disconnect() {
        _ = tokenStore.delete()
        RefreshStateStore().clear(provider: .codex)
        state = .notConnected
        NotificationCenter.default.post(name: .limitsProviderConnectionChanged, object: nil)
    }
}
