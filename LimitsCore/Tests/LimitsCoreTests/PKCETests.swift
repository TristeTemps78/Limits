import XCTest
@testable import LimitsCore

final class PKCETests: XCTestCase {
    /// RFC 7636 Appendix B's own worked example — independently reconfirmed here with
    /// `openssl dgst -sha256` before writing this test, so this isn't just trusting
    /// memory of the RFC text.
    func testCodeChallengeMatchesKnownRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        XCTAssertEqual(PKCE.codeChallenge(forVerifier: verifier), expectedChallenge)
    }

    func testGeneratedVerifierLengthIsWithinRFC7636Range() {
        let pair = PKCE.generate()
        XCTAssertTrue((43...128).contains(pair.verifier.count), "verifier length \(pair.verifier.count) out of RFC 7636 range")
    }

    func testGeneratedVerifierUsesOnlyUnreservedBase64URLCharacters() {
        let pair = PKCE.generate()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in pair.verifier.unicodeScalars {
            XCTAssertTrue(allowed.contains(scalar), "unexpected character '\(scalar)' in verifier")
        }
    }

    func testGeneratedVerifierHasNoPadding() {
        let pair = PKCE.generate()
        XCTAssertFalse(pair.verifier.contains("="))
        XCTAssertFalse(pair.challenge.contains("="))
    }

    func testGeneratedChallengeMatchesItsOwnVerifier() {
        let pair = PKCE.generate()
        XCTAssertEqual(pair.challenge, PKCE.codeChallenge(forVerifier: pair.verifier))
    }

    func testTwoGeneratedPairsAreNotEqual() {
        let first = PKCE.generate()
        let second = PKCE.generate()
        XCTAssertNotEqual(first.verifier, second.verifier, "verifiers should be random, not fixed")
    }
}
