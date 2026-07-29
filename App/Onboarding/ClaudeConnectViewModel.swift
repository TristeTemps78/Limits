import Foundation
import AuthenticationServices
import LimitsCore

/// Drives Claude's "manual paste" OAuth flow (PLAN.md §3.1): open the authorize page,
/// the user logs in and copies a `code#state` string shown on the callback page, then
/// pastes it back here. There is no redirect into the app — `ASWebAuthenticationSession`
/// is used purely to present the login page in a contained, cookie-capable browser
/// context (so an existing Safari session can carry over), with
/// `callbackURLScheme: nil` since nothing is ever meant to redirect back.
@MainActor
final class ClaudeConnectViewModel: NSObject, ObservableObject {
    @Published private(set) var state: AppOnboardingConnectionState = .notConnected
    @Published var pastedCode: String = ""

    private var pendingVerifier: String?
    private var expectedState: String?
    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationContext = WebAuthPresentationContext()
    private let tokenStore = TokenStore(provider: .claude)

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

        let url = ClaudeOAuth.authorizeURL(codeChallenge: pair.challenge, state: generatedState)

        state = .connecting
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            // Never fires with a usable callback — Claude's flow doesn't redirect
            // back into the app. Only reachable if the user dismisses the sheet or
            // the session errors before the login page even loads.
            guard let self, case .connecting = self.state else { return }
            self.state = .notConnected
        }
        session.presentationContextProvider = presentationContext
        webAuthSession = session
        session.start()
    }

    /// Cancels an in-flight attempt (e.g. the user backed out without pasting
    /// anything) so a stale PKCE verifier/state can't be reused by a later paste.
    func cancel() {
        webAuthSession?.cancel()
        webAuthSession = nil
        pendingVerifier = nil
        expectedState = nil
        pastedCode = ""
        if case .connecting = state {
            state = .notConnected
        }
    }

    func submitPastedCode() {
        guard let verifier = pendingVerifier, let expectedState else {
            state = .failed(message: "Aucune connexion en cours — relance depuis le bouton « Se connecter ».")
            return
        }

        switch ClaudeOAuth.parsePastedCode(pastedCode) {
        case .failure:
            state = .failed(message: "Code invalide. Vérifie que le texte complet (avant et après le #) a bien été copié.")
        case .success(let parsed):
            switch ClaudeOAuth.verifyState(received: parsed.state, expected: expectedState) {
            case .failure:
                state = .failed(message: "La connexion a expiré ou a été altérée — relance depuis le bouton « Se connecter ».")
            case .success:
                state = .exchangingToken
                webAuthSession?.cancel()
                webAuthSession = nil
                Task { await exchange(code: parsed.code, parsedState: parsed.state, verifier: verifier) }
            }
        }
    }

    private func exchange(code: String, parsedState: String, verifier: String) async {
        let result = await ClaudeOAuth.exchange(code: code, state: parsedState, codeVerifier: verifier)
        switch result {
        case .success(let response):
            guard let refreshToken = response.refreshToken else {
                state = .failed(message: "Réponse de connexion incomplète (aucun refresh token reçu). Réessaie.")
                return
            }
            let tokens = StoredTokens(
                accessToken: response.accessToken,
                refreshToken: refreshToken,
                expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            )
            guard case .success = tokenStore.save(tokens) else {
                state = .failed(message: "Connexion réussie mais impossible d'enregistrer les identifiants sur cet appareil.")
                return
            }
            pastedCode = ""
            pendingVerifier = nil
            expectedState = nil
            state = .connected
            NotificationCenter.default.post(name: .limitsProviderConnectionChanged, object: nil)
        case .failure:
            state = .failed(message: "Échec de la connexion. Vérifie ta connexion réseau et réessaie.")
        }
    }

    func disconnect() {
        _ = tokenStore.delete()
        state = .notConnected
        NotificationCenter.default.post(name: .limitsProviderConnectionChanged, object: nil)
    }
}
