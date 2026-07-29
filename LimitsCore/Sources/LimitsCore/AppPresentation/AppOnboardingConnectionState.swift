import Foundation

/// Per-provider connection-attempt state for the onboarding screen. The two
/// providers are fully independent (PLAN.md §1: "on doit pouvoir n'en connecter
/// qu'un") — each provider's onboarding view owns its own instance of this state,
/// never a shared one.
public enum AppOnboardingConnectionState: Equatable, Sendable {
    case notConnected
    /// Browser session open (Claude: waiting for the user to paste `code#state`;
    /// Codex: waiting on the local callback server + browser redirect).
    case connecting
    case exchangingToken
    case connected
    /// `message` is always a fixed, pre-written string — never the raw error, never
    /// anything that could contain a code/state/token (AGENTS.md rule 5/6). Building
    /// that message is the view model's job, not this type's.
    case failed(message: String)

    /// Whether starting a new connection attempt makes sense from this state.
    /// Starting a second attempt while one is already `connecting`/`exchangingToken`
    /// would leak a second `ASWebAuthenticationSession`/`LocalCallbackServer` — the
    /// view model should check this before firing another attempt, not rely on the
    /// button merely being disabled.
    public var canStartNewAttempt: Bool {
        switch self {
        case .notConnected, .connected, .failed:
            return true
        case .connecting, .exchangingToken:
            return false
        }
    }
}
