import Foundation

/// Extracts `chatgpt_account_id` from a Codex `id_token` JWT, matching
/// `codex-rs/login/src/success_page.rs::jwt_auth_claims` — no signature verification
/// (the token arrived over TLS directly from the token endpoint we just called;
/// codex-rs itself doesn't verify the signature client-side either).
public enum CodexIDToken {
    private static let claimNamespace = "https://api.openai.com/auth"
    private static let accountIDKey = "chatgpt_account_id"

    /// Extracts the `chatgpt_account_id` claim. Never includes the token or the
    /// extracted id in its error path — callers are responsible for keeping the
    /// returned value out of logs (AGENTS.md rule 5/6).
    public static func accountID(fromIDToken idToken: String) -> Result<String, CodexIDTokenError> {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            return .failure(.malformed)
        }
        guard let payloadData = base64URLDecode(String(segments[1])) else {
            return .failure(.malformed)
        }
        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return .failure(.malformed)
        }
        guard
            let namespace = json[claimNamespace] as? [String: Any],
            let accountID = namespace[accountIDKey] as? String,
            !accountID.isEmpty
        else {
            return .failure(.claimMissing)
        }
        return .success(accountID)
    }

    /// JWT segments are base64url **without padding** by spec — a classic pitfall is
    /// feeding that straight to `Data(base64Encoded:)`, which requires padding and
    /// simply returns `nil` (not a helpful error) on an unpadded string. This
    /// restores the `=` padding before decoding.
    static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

public enum CodexIDTokenError: Error, LocalizedError, Equatable {
    case malformed
    case claimMissing

    public var errorDescription: String? {
        switch self {
        case .malformed:
            return "id_token illisible."
        case .claimMissing:
            return "Identifiant de compte introuvable dans la réponse."
        }
    }
}
