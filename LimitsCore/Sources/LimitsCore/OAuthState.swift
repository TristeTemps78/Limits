import Foundation

/// Anti-CSRF `state` nonce generation and verification.
///
/// `state` is not a secret — it round-trips through the browser's authorize URL and,
/// for Claude, through the code the user copies and pastes back in clear text. Its
/// job is just to be unpredictable enough that a third party can't forge a matching
/// callback. Constant-time comparison here is defense-in-depth, not protection of a
/// secret value.
public enum OAuthState {
    /// 32 random bytes, base64url, no padding — same generation approach as
    /// `PKCE.generate()`.
    public static func generate() -> String {
        PKCE.base64URLEncode(PKCE.randomBytes(count: 32))
    }

    /// Constant-time equality check. Returns `false` immediately on a length
    /// mismatch — this leaks the length via timing, but the length of a `state`
    /// value we ourselves generated is not sensitive, so this is an acceptable
    /// simplification over a fully length-independent comparison.
    public static func verify(received: String, expected: String) -> Bool {
        let receivedBytes = Array(received.utf8)
        let expectedBytes = Array(expected.utf8)
        guard receivedBytes.count == expectedBytes.count else {
            return false
        }
        var diff: UInt8 = 0
        for index in 0..<expectedBytes.count {
            diff |= receivedBytes[index] ^ expectedBytes[index]
        }
        return diff == 0
    }
}
