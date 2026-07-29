import AuthenticationServices
import UIKit

/// Anchor window for `ASWebAuthenticationSession`. Falls back to a bare
/// `ASPresentationAnchor()` only if no key window can be found (shouldn't happen in
/// practice — the session is always started from a foreground UI action) rather than
/// crashing.
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return keyWindow ?? ASPresentationAnchor()
    }
}
