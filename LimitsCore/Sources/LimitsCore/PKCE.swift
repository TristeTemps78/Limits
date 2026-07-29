import Foundation
import CryptoKit
import Security

/// PKCE (RFC 7636) code verifier/challenge generation, shared by both providers —
/// this is pure crypto with no network or provider-specific behavior, so sharing it
/// (unlike the HTTP client — see ClaudeOAuth.swift/CodexOAuth.swift, deliberately
/// **not** shared) doesn't risk mixing up provider-specific request shapes.
public enum PKCE {
    public struct Pair: Equatable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String, challenge: String) {
            self.verifier = verifier
            self.challenge = challenge
        }
    }

    /// Generates a verifier of `byteCount` random bytes (default 64, matching
    /// codex-rs's own generator — see docs/oauth-verification-2026-07-29.md, PKCE
    /// row) base64url-encoded without padding (~86 chars, within RFC 7636's 43-128
    /// range) and its S256 challenge.
    public static func generate(byteCount: Int = 64) -> Pair {
        let verifier = base64URLEncode(randomBytes(count: byteCount))
        let challenge = codeChallenge(forVerifier: verifier)
        return Pair(verifier: verifier, challenge: challenge)
    }

    /// S256 challenge for a given verifier: `base64url(SHA256(ascii(verifier)))`, no
    /// padding. Exposed separately from `generate()` so it can be checked against a
    /// known RFC 7636 test vector without depending on random generation.
    public static func codeChallenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes practically never fails on Apple platforms, but if
            // it ever does, fall back to Swift's own CSPRNG-backed generator rather
            // than crash — still cryptographically sound entropy for a PKCE verifier.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
